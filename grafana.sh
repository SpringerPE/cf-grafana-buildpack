#!/usr/bin/env bash

export GRAFANA_ROOT=/home/vcap/deps/grafana
export SQLPROXY_ROOT=/home/vcap/deps/cloud_sql_proxy
export PATH=${PATH}:${GRAFANA_ROOT}/bin:${SQLPROXY_ROOT}
export APP_ROOT=${HOME}
export AUTH_ROOT="/home/vcap/auth"

###

export DOMAIN=${DOMAIN:-$(jq -r '.uris[0]' <<<"${VCAP_APPLICATION}")}
export ADMIN_USER=${ADMIN_USER:-admin}
export ADMIN_PASS=${ADMIN_PASS:-admin}
export EMAIL=${EMAIL:-grafana@$DOMAIN}
export DB_BINDING_NAME=${MAIN_DB_BINDING_NAME:-database}

export DB_TYPE="sqlite3"
export DB_USER="root"
export DB_HOST="127.0.0.1"
export DB_PASS=""
export DB_PORT="3306"
export DB_NAME="grafana"
export DB_CA_CERT=""
export DB_CLIENT_CERT=""
export DB_CLIENT_KEY=""
export DB_CERT_NAME=""
export DB_TLS="skip-verify"
export DB_PROXY_INSTANCE=""

export SESSION_DB_TYPE="file"
export SESSION_DB_CONFIG="sessions"

###

get_db_vcap_service() {
    local binding_name="${1}"
    local rvalue
    
    if [ -z "${binding_name}" ] || [ "${binding_name}" == "null" ]
    then
        # search for a sql service looking at the label
        jq '[.[][] | select(.credentials.uri | split(":")[0] == ("mysql","postgres"))] | first' <<<"${VCAP_SERVICES}"
    else
        jq -e --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${VCAP_SERVICES}"
        rvalue=$?
        if [ ${rvalue} != 0 ]
        then
            jq '[.[][] | select(.credentials.uri | split(":")[0] == ("mysql","postgres"))] | first' <<<"${VCAP_SERVICES}"
        fi
    fi
}

get_db_vcap_service_type() {
    local db="${1}"
    jq -e -r '.credentials.uri | split(":")[0]' <<<"${db}"
}

is_service_on_GCP() {
    local db="${1}"
    jq -e '.tags | contains(["gcp"])' <<<"${db}" >/dev/null
}


export_DB_params() {
    local db="${1}"

    local uri
    export DB_TYPE=$(get_db_vcap_service_type "${db}")

    if is_service_on_GCP "${db}"
    then
        # GCP service broker
        export DB_HOST=$(jq -r '.credentials.host' <<<"${db}")
        export DB_USER=$(jq -r '.credentials.Username' <<<"${db}")
        export DB_PASS=$(jq -r '.credentials.Password' <<<"${db}")
        export DB_NAME=$(jq -r '.credentials.database_name' <<<"${db}")
        if [ "${DB_TYPE}" == "mysql" ]
        then
            export DB_PORT="3306"
        elif [ "${DB_TYPE}" == "postgres" ]
        then
            export DB_PORT="5432"
        fi
        uri="${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    else
        # Other service broker
        uri=$(jq -r '.credentials.uri' <<<"${db}")
        export DB_USER=$(jq -r '.credentials.uri | split("://")[1] | split(":")[0]' <<<"${db}")
        export DB_PASS=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[0]' <<<"${db}")
        export DB_HOST=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[1] | split("/")[0]' <<<"${db}")
        export DB_NAME=$(jq -r '.credentials.uri | split("://")[1] | split(":")[1] | split("@")[1] | split("/")[1] | split("?")[0]' <<<"${db}")
    fi
    echo "${uri}"
}

export_DB_params_secure() {
    local db="${1}"

    local kind=$(get_db_vcap_service_type "${db}")
    mkdir -p ${AUTH_ROOT}
    if jq -r -e '.credentials.ClientCert'  <<<"${db}" >/dev/null
    then
        jq -r '.credentials.CaCert' <<<"${db}" > "${AUTH_ROOT}/ca.crt"
        jq -r '.credentials.ClientCert' <<<"${db}" > "${AUTH_ROOT}/client.crt"
        jq -r '.credentials.ClientKey' <<<"${db}" > "${AUTH_ROOT}/client.key"
        export DB_CA_CERT="${AUTH_ROOT}/ca.crt"
        export DB_CLIENT_CERT="${AUTH_ROOT}/client.crt"
        export DB_CLIENT_KEY="${AUTH_ROOT}/client.key"
        if [ "${kind}" == "mysql" ]
        then
            export DB_TLS="true"
        elif [ "${kind}" == "postgres" ]
        then
            export DB_TLS="require"
        fi
    fi
    echo $DB_TLS
}

export_DB_proxy() {
    local db="${1}"

    if is_service_on_GCP "${db}"
    then
        jq -r '.credentials.PrivateKeyData' <<<"${db}" | base64 -d > "${AUTH_ROOT}/auth.json"
        export DB_HOST="127.0.0.1"
        DB_PROXY_INSTANCE=$(jq -r '.credentials.ProjectId + ":" + .credentials.region + ":" + .credentials.instance_name' <<<"${db}")
        export DB_PROXY_INSTANCE="${DB_PROXY_INSTANCE}=tcp:${DB_PORT}"
        export DB_CERT_NAME=$(jq -r '.credentials.ProjectId + ":" + .credentials.instance_name' <<<"${db}")
        if [ "${kind}" == "mysql" ]
        then
            export DB_TLS="false"
        elif [ "${kind}" == "postgres" ]
        then
            export DB_TLS="disable"
        fi
    fi
}


export_DB_session() {
    if [ "${DB_TYPE}" == "mysql" ]
    then
        export SESSION_DB_TYPE="mysql"
        export SESSION_DB_CONFIG="${DB_USER}:${DB_PASS}@tcp(${DB_HOST}:${DB_PORT})/${DB_NAME}"
    elif [ "${DB_TYPE}" == "postgres" ]
    then
        export SESSION_DB_TYPE="postgres"
        export SESSION_DB_CONFIG="user=${DB_USER} password=${DB_PASS} host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME}"
    fi
}

###

set_DB_settings() {
    local binding="${1}"
    local uri
    local rvalue
    local db

    db=$(get_db_vcap_service "${binding}")
    rvalue=$?
    if [ "${rvalue}" -eq 0 ] && [ -n "${db}" ]
    then
        export_DB_params "${db}" >/dev/null
        export_DB_params_secure "${db}" >/dev/null
        export_DB_proxy "${db}"
        # Set parameters for session
        export_DB_session
    fi
}

random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
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

# exec grafana and create the datasources
launch() {
    local backgroud="${1}"
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


###

echo "Initializing settings ..."
set_DB_settings "${DB_BINDING_NAME}"
set_seed_secrets

if [ -f "${AUTH_ROOT}/auth.json" ]
then
    echo "Launching local sql proxy ..."
    launch bg cloud_sql_proxy -instances="${DB_PROXY_INSTANCE}" -credential_file="${AUTH_ROOT}/auth.json" -verbose -term_timeout=30s -ip_address_types=PRIVATE,PUBLIC
fi

echo "Launching grafana server..."
cd ${GRAFANA_ROOT}
if [ -f "${APP_ROOT}/grafana.ini" ]
then
    launch bg grafana-server -config=${APP_ROOT}/grafana.ini
else
    launch bg grafana-server
fi

