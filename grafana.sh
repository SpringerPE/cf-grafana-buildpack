#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/vcap"
export AUTH_ROOT="${ROOT}/auth"
export GRAFANA_ROOT=$(find ${ROOT}/deps -name grafana -type d -maxdepth 2)
export SQLPROXY_ROOT=$(find ${ROOT}/deps -name cloud_sql_proxy -type d -maxdepth 2)
export GRAFANA_CFG_INI="${ROOT}/app/grafana.ini"
export GRAFANA_CFG_PLUGINS="${ROOT}/app/plugins.txt"
export PATH=${PATH}:${GRAFANA_ROOT}/bin:${SQLPROXY_ROOT}

### Defined here to avoid override

export GF_PATHS_PLUGINS="${ROOT}/app/plugins"
export GF_PATHS_PROVISIONING="${ROOT}/app"
export GF_PATHS_LOGS="${ROOT}/logs"
export GF_PATHS_DATA="${ROOT}/tmp"
export GF_ENTERPRISE_LICENSE_PATH="${ROOT}/app/license"

### Bindings

export DB_BINDING_NAME=${DB_BINDING_NAME:-}
export MAIN_DB_BINDING_NAME=${MAIN_DB_BINDING_NAME:-main}
export SESSION_DB_BINDING_NAME=${SESSION_DB_BINDING_NAME:-session}

# Exported variables used in default.ini config file
export DOMAIN=${DOMAIN:-$(jq -r '.uris[0]' <<<"${VCAP_APPLICATION}")}
export ADMIN_USER=${ADMIN_USER:-admin}
export ADMIN_PASS=${ADMIN_PASS:-admin}
export EMAIL=${EMAIL:-grafana@$DOMAIN}
# See reset_DB for default values!
export DB_TYPE=""
export DB_USER=""
export DB_HOST=""
export DB_PASS=""
export DB_PORT=""
export DB_NAME=""
export DB_CA_CERT=""
export DB_CLIENT_CERT=""
export DB_CLIENT_KEY=""
export DB_CERT_NAME=""
export DB_TLS=""
export SESSION_DB_TYPE="file"
export SESSION_DB_CONFIG="sessions"


###

# exec process in bg or fg
launch() {
    local background="${1}"
    shift
    (
        echo "Launching pid=$$: '$@'"
        {
            exec $@  2>&1;
        }
    ) &
    pid=$!
    sleep 30
    if ! ps -p ${pid} >/dev/null 2>&1; then
        echo
        echo "Error launching '$@'."
        rvalue=1
    else
        if [[ -z "${background}" ]] && [[ "${background}" == "bg" ]]
        then
            wait ${pid} 2>/dev/null
            rvalue=$?
            echo "Finish pid=${pid}: ${rvalue}"
        else
            rvalue=0
            echo "Background pid=${pid}: 0"
        fi
    fi
    return ${rvalue}
}

random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
}

get_binding_service() {
    local binding_name="${1}"
    local rvalue
    
    jq --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${VCAP_SERVICES}"
}

get_db_vcap_service() {
    local binding_name="${1}"
    local rvalue
    
    if [ -z "${binding_name}" ] || [ "${binding_name}" == "null" ]
    then
        # search for a sql service looking at the label
        jq '[.[][] | select(.credentials.uri | split(":")[0] == ("mysql","postgres"))] | first' <<<"${VCAP_SERVICES}"
    else
        get_binding_service "${binding_name}"
    fi
}

get_db_vcap_service_type() {
    local db="${1}"
    jq -r '.credentials.uri | split(":")[0]' <<<"${db}"
}

service_on_GCP() {
    local db="${1}"
    jq -e '.tags | contains(["gcp"])' <<<"${db}" >/dev/null
}

reset_env_DB() {
    DB_TYPE="sqlite3"
    DB_USER="root"
    DB_HOST="127.0.0.1"
    DB_PASS=""
    DB_PORT="3306"
    DB_NAME="grafana"
    DB_CA_CERT=""
    DB_CLIENT_CERT=""
    DB_CLIENT_KEY=""
    DB_CERT_NAME=""
    DB_TLS=""
}

export_DB() {
    local db="${1}"
    local uri

    DB_TYPE=$(get_db_vcap_service_type "${db}")
    if service_on_GCP "${db}"
    then
        # GCP service broker
        DB_HOST=$(jq -r '.credentials.host' <<<"${db}")
        DB_USER=$(jq -r '.credentials.Username' <<<"${db}")
        DB_PASS=$(jq -r '.credentials.Password' <<<"${db}")
        DB_NAME=$(jq -r '.credentials.database_name' <<<"${db}")
        if [ "${DB_TYPE}" == "mysql" ]
        then
            DB_PORT="3306"
            DB_TLS="false"
        elif [ "${DB_TYPE}" == "postgres" ]
        then
            DB_PORT="5432"
            DB_TLS="disable"
        fi
        uri="${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    else
        # Other service broker
        uri=$(jq -r '.credentials.uri' <<<"${db}")
        DB_USER=$(jq -r '.credentials.uri | split("://")[1] | split(":")[0]' <<<"${db}")
        DB_PASS=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[0]' <<<"${db}")
        DB_HOST=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[1] | split("/")[0]' <<<"${db}")
        DB_NAME=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[1] | split("/")[1] | split("?")[0]' <<<"${db}")
        # TODO parse TLS params
    fi
    # TLS
    mkdir -p ${AUTH_ROOT}
    if jq -r -e '.credentials.ClientCert'  <<<"${db}" >/dev/null
    then
        jq -r '.credentials.CaCert' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-ca.crt"
        jq -r '.credentials.ClientCert' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-client.crt"
        jq -r '.credentials.ClientKey' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-client.key"
        DB_CA_CERT="${AUTH_ROOT}/${DB_NAME}-ca.crt"
        DB_CLIENT_CERT="${AUTH_ROOT}/${DB_NAME}-client.crt"
        DB_CLIENT_KEY="${AUTH_ROOT}/${DB_NAME}-client.key"
        if [ "${DB_TYPE}" == "mysql" ]
        then
            service_on_GCP "${db}" && DB_TLS="true" || DB_TLS="skip-verify"
        elif [ "${DB_TYPE}" == "postgres" ]
        then
            service_on_GCP "${db}" && DB_TLS="verify-full" || DB_TLS="require"
        fi
        service_on_GCP "${db}" && DB_CERT_NAME=$(jq -r '.credentials.ProjectId + ":" + .credentials.instance_name' <<<"${db}")
    fi
    echo "${uri}"
}


# Given a DB from vcap services, defines the proxy files ${DB_NAME}-auth.json and
# ${AUTH_ROOT}/${DB_NAME}.proxy
set_DB_proxy() {
    local db="${1}"

    local proxy

    # Proxy on Google, creates 2 files if needed
    if service_on_GCP "${db}"
    then
        jq -r '.credentials.PrivateKeyData' <<<"${db}" | base64 -d > "${AUTH_ROOT}/${DB_NAME}-auth.json"
        proxy=$(jq -r '.credentials.ProjectId + ":" + .credentials.region + ":" + .credentials.instance_name' <<<"${db}")
        echo "${proxy}=tcp:${DB_PORT}" > "${AUTH_ROOT}/${DB_NAME}.proxy"
        [ "${DB_TYPE}" == "mysql" ] && DB_TLS="false"
        [ "${DB_TYPE}" == "postgres" ] && DB_TLS="disable"
        DB_HOST="127.0.0.1"
    fi
}

# Find out the SB database for sessions
set_session_DB() {
    local sessiondb

    sessiondb=$(get_binding_service "${SESSION_DB_BINDING_NAME}")
    [ -z "${sessiondb}" ] && sessiondb=$(get_db_vcap_service "${DB_BINDING_NAME}")
    if [ -n "${sessiondb}" ]
    then
        export_DB "${sessiondb}" >/dev/null
        set_DB_proxy "${sessiondb}"
        if [ "${DB_TYPE}" == "mysql" ]
        then
            SESSION_DB_TYPE="mysql"
            SESSION_DB_CONFIG="${DB_USER}:${DB_PASS}@tcp(${DB_HOST}:${DB_PORT})/${DB_NAME}"
        elif [ "${DB_TYPE}" == "postgres" ]
        then
            SESSION_DB_TYPE="postgres"
            SESSION_DB_CONFIG="user=${DB_USER} password=${DB_PASS} host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME}"
        fi
        # TODO TLS
   fi
}

# Find out the main DB
set_main_DB() {
    local db

    db=$(get_binding_service "${MAIN_DB_BINDING_NAME}")
    [ -z "${db}" ] && db=$(get_db_vcap_service "${DB_BINDING_NAME}")
    if [ -n "${db}" ]
    then
        export_DB "${db}" >/dev/null
        set_DB_proxy "${db}"
    fi
}

# Sets all DB
set_sql_databases() {
    echo "Initializing DB settings from service instances ..."
    reset_env_DB
    set_session_DB
    reset_env_DB
    set_main_DB
}

set_seed_secrets() {
    if [[ -z "${SECRET_KEY}" ]]
    then
        # Take it from the space_id. It is not random!
        export SECRET_KEY=$(jq -r '.space_id' <<<"${VCAP_APPLICATION}")
        echo "######################################################################"
        echo "WARNING: SECRET_KEY environment variable not defined!"
        echo "Used for signing some datasource settings like secrets and passwords."
        echo "Cannot be changed without requiring an update to datasource settings to re-encode them."
        echo "Please define it in grafana.ini or using an environment variable!"
        echo "Generated SECRET_KEY=${SECRET_KEY}"
        echo "######################################################################"
    fi
}

install_grafana_plugins() {
    echo "Initializing plugins from ${GRAFANA_CFG_PLUGINS} ..."
    if [ -f "${GRAFANA_CFG_PLUGINS}" ]
    then
        while read -r pluginid pluginversion
        do
            if [ -n "${pluginid}" ]
            then
                echo "Installing ${pluginid} ${pluginversion} ..."
                grafana-cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install ${pluginid} ${pluginversion}
            fi
        done <<< $(grep -v '^#' "${GRAFANA_CFG_PLUGINS}")
    fi
}

run_sql_proxies() {
    local instance dbname
    for file in ${AUTH_ROOT}/*.proxy
    do
        dbname=$(basename "${file}" | sed -n 's/^\(.*\)\.proxy$/\1/p')
        instance=$(head "${file}")
        echo "Launching local sql proxy for instance ${instance} ..."
        launch bg cloud_sql_proxy -instances="${instance}" -credential_file="${AUTH_ROOT}/${dbname}-auth.json" -verbose -term_timeout=30s -ip_address_types=PRIVATE,PUBLIC
    done
}


run_grafana_server() {
    echo "Launching grafana server ..."
    pushd "${GRAFANA_ROOT}" >/dev/null
        if [ -f "${GRAFANA_CFG_INI}" ]
        then
            launch bg grafana-server -config=${GRAFANA_CFG_INI}
        else
            launch bg grafana-server
        fi
    popd
}


################################################################################

set_sql_databases
set_seed_secrets
install_grafana_plugins
run_sql_proxies
run_grafana_server

