#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -euo pipefail

# See bin/finalize to check predefined vars
ROOT="/home/vcap"
export AUTH_ROOT="${ROOT}/auth"
#export GRAFANA_ROOT=$(find ${ROOT}/deps -name grafana -type d -maxdepth 2)
export GRAFANA_ROOT=$GRAFANA_ROOT
#export SQLPROXY_ROOT=$(find ${ROOT}/deps -name cloud_sql_proxy -type d -maxdepth 2)
export SQLPROXY_ROOT=$SQLPROXY_ROOT
export YQ_ROOT=${YQ_ROOT}
export APP_ROOT="${ROOT}/app"
export GRAFANA_DASHBOARD_ROOT=${APP_ROOT}/dashboards
export GRAFANA_ALERTING_ROOT=${APP_ROOT}/alerting
export GRAFANA_CFG_INI="${ROOT}/app/grafana.ini"
export GRAFANA_CFG_PLUGINS="${ROOT}/app/plugins.txt"
export GRAFANA_USER_CONFIG_ROOT="${ROOT}/app/users"
export PATH=${PATH}:${GRAFANA_ROOT}/bin:${SQLPROXY_ROOT}:${YQ_ROOT}

### Bindings
# Prometheus datasource
export DATASOURCE_BINDING_NAME="${DATASOURCE_BINDING_NAME:-datasource}"
# SQL DB
export DB_BINDING_NAME="${DB_BINDING_NAME:-}"

# Exported variables used in default.ini config file
export DOMAIN=${DOMAIN:-$(jq -r '.uris[0]' <<<"${VCAP_APPLICATION}")}
export URL="${URL:-http://$DOMAIN/}"
export HOME_DASHBOARD_UID="${HOME_DASHBOARD_UID:-home}"
export HOME_ORG_ID="${HOME_ORG_ID:-1}"
export ADMIN_USER="${ADMIN_USER:-${GF_SECURITY_ADMIN_USER:-admin}}"
export ADMIN_PASS="${ADMIN_PASS:-${GF_SECURITY_ADMIN_PASSWORD:-admin}}"
export EMAIL="${EMAIL:-grafana@$DOMAIN}"
export SECRET_KEY="${SECRET_KEY:-}"
export DEFAULT_DATASOURCE_EDITABLE="${DEFAULT_DATASOURCE_EDITABLE:-false}"
export DEFAULT_DATASOURCE_TIMEINTERVAL="${DEFAULT_DATASOURCE_TIMEINTERVAL:-60s}"

# Variables exported, they are automatically filled from the 
# service broker instances.
# See reset_DB for default values!
export DB_TYPE="sqlite3"
export DB_USER="root"
export DB_HOST=""
export DB_PASS=""
export DB_PORT=""
export DB_NAME="grafana"
export DB_CA_CERT=""
export DB_CLIENT_CERT=""
export DB_CLIENT_KEY=""
export DB_CERT_NAME=""
export DB_TLS=""


###

# exec process in bg
launch() {
    (
        echo "Launching pid=$$: '$@'"
        {
            exec $@  2>&1;
        }
    ) &
    pid=$!
    sleep 15
    if ! ps -p ${pid} >/dev/null 2>&1
    then
        echo
        echo "Error launching '$@'."
        rvalue=1
    else
        echo "Pid=${pid} running"
        rvalue=0
    fi
    return ${rvalue}
}


random_string() {
    (
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1 || true
    )
}


get_binding_service() {
    local binding_name="${1}"
    jq --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${VCAP_SERVICES}"
}


get_db_vcap_service() {
    local binding_name="${1}"

    if [[ -z "${binding_name}" ]] || [[ "${binding_name}" == "null" ]]
    then
        # search for a sql service looking at the label
        jq '[.[][] | select(.credentials.uri) | select(.credentials.uri | split(":")[0] == ("mysql","postgres","postgresql"))] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
    else
        get_binding_service "${binding_name}"
    fi
}


get_db_vcap_service_type() {
    local db="${1}"
    jq -r '.credentials.uri | split(":")[0]' <<<"${db}"
}


get_prometheus_vcap_service() {
    # search for a sql service looking at the label
    jq '[.[][] | select(.credentials.prometheus) ] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
}


reset_env_DB() {
    DB_TYPE="sqlite3"
    DB_USER="root"
    DB_HOST=""
    DB_PASS=""
    DB_PORT=""
    DB_NAME="grafana"
    DB_CA_CERT=""
    DB_CLIENT_CERT=""
    DB_CLIENT_KEY=""
    DB_CERT_NAME=""
    DB_TLS=""
}


set_env_DB() {
    local db="${1}"
    local uri=""

    DB_TYPE=$(get_db_vcap_service_type "${db}")
    if [[ $DB_TYPE == "postgresql" ]]
    then
	DB_TYPE="postgres"
    fi

    uri="${DB_TYPE}://"
    if ! DB_USER=$(jq -r -e '.credentials.Username' <<<"${db}")
    then
        DB_USER=$(jq -r -e '.credentials.uri |
            split("://")[1] | split(":")[0]' <<<"${db}") || DB_USER=''
    fi
    uri="${uri}${DB_USER}"
    if ! DB_PASS=$(jq -r -e '.credentials.Password' <<<"${db}")
    then
        DB_PASS=$(jq -r -e '.credentials.uri |
            split("://")[1] | split(":")[1] |
            split("@")[0]' <<<"${db}") || DB_PASS=''
    fi
    uri="${uri}:${DB_PASS}"
    if ! DB_HOST=$(jq -r -e '.credentials.host' <<<"${db}")
    then
        DB_HOST=$(jq -r -e '.credentials.uri |
            split("://")[1] | split(":")[1] |
            split("@")[1] |
            split("/")[0]' <<<"${db}") || DB_HOST=''
    fi
    uri="${uri}@${DB_HOST}"
    if [[ "${DB_TYPE}" == "mysql" ]]
    then
        DB_PORT="3306"
        uri="${uri}:${DB_PORT}"
        DB_TLS="false"
    elif [[ "${DB_TYPE}" == "postgres" ]]
    then
        DB_PORT="5432"
        uri="${uri}:${DB_PORT}"
        DB_TLS="disable"
    fi
    if ! DB_NAME=$(jq -r -e '.credentials.database_name' <<<"${db}")
    then
        DB_NAME=$(jq -r -e '.credentials.uri |
            split("://")[1] | split("/")[1] |
            split("?")[0]' <<<"${db}") || DB_NAME=''
    fi
    uri="${uri}/${DB_NAME}"
    # TLS
    mkdir -p ${AUTH_ROOT}
    if jq -r -e '.credentials.ClientCert' <<<"${db}" >/dev/null
    then
        jq -r '.credentials.CaCert' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-ca.crt"
        jq -r '.credentials.ClientCert' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-client.crt"
        jq -r '.credentials.ClientKey' <<<"${db}" > "${AUTH_ROOT}/${DB_NAME}-client.key"
        DB_CA_CERT="${AUTH_ROOT}/${DB_NAME}-ca.crt"
        DB_CLIENT_CERT="${AUTH_ROOT}/${DB_NAME}-client.crt"
        DB_CLIENT_KEY="${AUTH_ROOT}/${DB_NAME}-client.key"
        if instance=$(jq -r -e '.credentials.instance_name' <<<"${db}")
        then
            DB_CERT_NAME="${instance}"
            if project=$(jq -r -e '.credentials.ProjectId' <<<"${db}")
            then
                # Google GCP format
                DB_CERT_NAME="${project}:${instance}"
            fi
            [[ "${DB_TYPE}" == "mysql" ]] && DB_TLS="true"
            [[ "${DB_TYPE}" == "postgres" ]] && DB_TLS="verify-full"
        else
            DB_CERT_NAME=""
            [[ "${DB_TYPE}" == "mysql" ]] && DB_TLS="skip-verify"
            [[ "${DB_TYPE}" == "postgres" ]] && DB_TLS="require"
        fi
    fi
    echo "${uri}"
}


# Given a DB from vcap services, defines the proxy files ${DB_NAME}-auth.json and
# ${AUTH_ROOT}/${DB_NAME}.proxy
set_DB_proxy() {
    local db="${1}"

    local proxy
    # If it is a google service, setup proxy by creating 2 files: auth.json and
    # cloudsql proxy configuration on ${DB_NAME}.proxy
    # It will also overwrite the variables to point to localhost
    if jq -r -e '.tags | contains(["gcp"])' <<<"${db}" >/dev/null
    then
        jq -r '.credentials.PrivateKeyData' <<<"${db}" | base64 -d > "${AUTH_ROOT}/${DB_NAME}-auth.json"
        proxy=$(jq -r '.credentials.ProjectId + ":" + .credentials.region + ":" + .credentials.instance_name' <<<"${db}")
        echo "${proxy}=tcp:${DB_PORT}" > "${AUTH_ROOT}/${DB_NAME}.proxy"
        [[ "${DB_TYPE}" == "mysql" ]] && DB_TLS="false"
        [[ "${DB_TYPE}" == "postgres" ]] && DB_TLS="disable"
        DB_HOST="127.0.0.1"
    fi
    echo "${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
}


# Sets all DB
set_sql_databases() {
    local db

    echo "Initializing DB settings from service instances ..."
    reset_env_DB

    db=$(get_db_vcap_service "${DB_BINDING_NAME}")
    if [[ -n "${db}" ]]
    then
        set_env_DB "${db}" >/dev/null
        set_DB_proxy "${db}" >/dev/null
    fi
}


set_vcap_datasource_prometheus() {
    local datasource="${1}"

    local label=$(jq -r '.label' <<<"${datasource}")
    local name=$(jq -r '.name' <<<"${datasource}")
    local user=$(jq -r '.credentials.prometheus.user | select (.!=null)' <<<"${datasource}")
    local pass=$(jq -r '.credentials.prometheus.password | select (.!=null)' <<<"${datasource}")
    local url=$(jq -r '.credentials.prometheus.url' <<<"${datasource}")
    local auth="true"

    [[ -z "${user}" ]] && auth="false"
    mkdir -p "${APP_ROOT}/datasources"

    # Be careful, this is a HERE doc with tabs indentation!!
    cat <<-EOF > "${APP_ROOT}/datasources/${HOME_ORG_ID}-${name}.yml"
	apiVersion: 1
	
	# list of datasources that should be deleted from the database
	deleteDatasources:
	- name: ${name}
	  orgId: ${HOME_ORG_ID}
	
	# list of datasources to insert/update depending
	# what's available in the database
	datasources:
	- name: ${name}
	  type: prometheus
	  access: proxy
	  orgId: ${HOME_ORG_ID}
	  url: "${url}"
	  basicAuth: ${auth}
	  basicAuthUser: ${user}
	  jsonData:
	    timeInterval: "${DEFAULT_DATASOURCE_TIMEINTERVAL}"
	  secureJsonData:
	    basicAuthPassword: ${pass}
	  withCredentials: false
	  isDefault: true
	  editable: ${DEFAULT_DATASOURCE_EDITABLE}
	EOF
}


set_vcap_datasource_alertmanager() {
    local datasource="${1}"

    local label=$(jq -r '.label' <<<"${datasource}")
    local name=$(jq -r '.name' <<<"${datasource}")
    local user=$(jq -r '.credentials.prometheus.user | select (.!=null)' <<<"${datasource}")
    local pass=$(jq -r '.credentials.prometheus.password | select (.!=null)' <<<"${datasource}")
    local url=$(jq -r '.credentials.alertmanager.url' <<<"${datasource}")
    local auth="true"

    [[ -z "${user}" ]] && auth="false"
    mkdir -p "${APP_ROOT}/datasources"

    # Be careful, this is a HERE doc with tabs indentation!!
    cat <<-EOF > "${APP_ROOT}/datasources/${HOME_ORG_ID}-${name}-alertmanager.yml"
	apiVersion: 1
	
	# list of datasources to insert/update depending
	# what's available in the database
	datasources:
	- name: ${name} AlertManager
	  type: camptocamp-prometheus-alertmanager-datasource
	  access: proxy
	  orgId: ${HOME_ORG_ID}
	  url: "${url}"
	  basicAuth: ${auth}
	  basicAuthUser: ${user}
	  secureJsonData:
	    basicAuthPassword: ${pass}
	  withCredentials: false
	  isDefault: false
	  editable: ${DEFAULT_DATASOURCE_EDITABLE}
	EOF

    echo "Installing camptocamp-prometheus-alertmanager-datasource ${GRAFANA_ALERTMANAGER_VERSION} ..."
    grafana-cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install camptocamp-prometheus-alertmanager-datasource ${GRAFANA_ALERTMANAGER_VERSION}
}

set_datasources() {
    local datasource
    local alertmanager_prometheus_exists

    datasource=$(get_binding_service "${DATASOURCE_BINDING_NAME}")
    [[ -z "${datasource}" ]] && datasource=$(get_prometheus_vcap_service)

    if [[ -n "${datasource}" ]]
    then
        set_vcap_datasource_prometheus "${datasource}"

        # Check if AlertManager for the Prometheus service instance has been enabled by the user first 
        # before installing the AlertManager Grafana plugin and configuring the AlertManager Grafana datasource
        alertmanager_prometheus_exists=$(jq -r '.credentials.alertmanager.url' <<<"${datasource}")
	  if [[ -n "${alertmanager_prometheus_exists}" ]] && [[ "${alertmanager_prometheus_exists}" != "null" ]]
	  then
            set_vcap_datasource_alertmanager "${datasource}"
        fi
    fi
}

replace_token_with_data() {
  token=$1
  data_pos=$2
  data_file=$3
  files_to_change=$4

  replace_commands=$(cat ${data_file} | tail -n +2 | awk -F "," "{ print \"s/\\{${token}}/\" \$${data_pos} \"/g\"}")

  replace_command_array=($replace_commands)
  filename_array=($files_to_change)
  filename_length=${#filename_array[@]}

  for (( pos=0; pos<filename_length; pos++ )); do
    filename="${filename_array[$pos]}"
    replace_command="${replace_command_array[$pos]}"
    echo "replace_command=${replace_command}, filename=${filename}"
    sed -i -- "${replace_command}" "${filename}"
  done
}

replace_headers_with_data() {
  data_file=$1
  files_to_change=$2

  headers=$(head -n 1 ${data_file})
  IFS=$','; header_array=($headers); unset IFS;
  header_length=${#header_array[@]}

  for (( header_pos=0; header_pos<header_length; header_pos++ )); do
    header="${header_array[$header_pos]}"
    echo "header=${header}"
    replace_token_with_data "${header}" $((header_pos + 1)) "${data_file}" "${files_to_change}"
  done
}

replace_placeholders_with_spaces() {
  for filename in $1; do
    sed -i -- 's/+/ /g' "${filename}"
  done
}

merge_alert_template_files() {
  base_file=$1
  for filename in $2; do
    cat "$filename" >> "$base_file"
    rm "$filename"
    rm "${filename}--"
  done
}

generate_alerts_from_templates() {
  template_dir=${GRAFANA_ALERTING_ROOT}/templates
  if [[ -d ${template_dir} ]]; then

    alert_groups_filename=${GRAFANA_ALERTING_ROOT}/alert-groups.yml
    cat > ${alert_groups_filename} << EOF
apiVersion: 1

groups:
EOF

    pushd "${template_dir}"

      for subdirectory in */; do

        pushd "${subdirectory}"

          if [ -f "group.yml.template" ]; then
            cat "group.yml.template" >> ${alert_groups_filename}
          fi

          for template in rule-*.yml.template; do

            alert_name="${template%.yml.template}"
            alert_data_file="${alert_name}.csv"

            if [ -f "$alert_data_file" ]; then
              echo "creating alerts from template ${template} with data from ${alert_data_file}"

              filenames=$(cat ${alert_data_file} | tail -n +2 | awk -F "," "{ print \"${GRAFANA_ALERTING_ROOT}/\" \$1 \"-${alert_name}.yml\" }")
              for filename in $filenames; do
                echo "creating alert file ${filename}"
                cp "${template}" "${filename}"
              done

              replace_headers_with_data "${alert_data_file}" "${filenames}"
              replace_placeholders_with_spaces "${filenames}"
              merge_alert_template_files "${alert_groups_filename}" "${filenames}"

            fi

          done
        popd
      done

    popd

    fi
}

pre-process() {
  local root_dir="${1}"
  if [[ -d "${root_dir}/pre-process" ]]
  then
      for pre_process_config_file in "${root_dir}/pre-process/*.yml"
      do
          files_to_process=$(yq eval '.files_to_process' ${pre_process_config_file})

          for replacement in $(yq eval -o=j -I=0 '.replacements[]' ${pre_process_config_file})
          do
              find=$(eval "echo $(echo $replacement | jq '.find')")
              replace=$(eval "echo $(echo $replacement | jq '.replace')")

              echo "Finding $find in ${root_dir}/${files_to_process} and replacing with $replace"
              sed_command="s/$find/$replace/g"
              sed -i -- $sed_command ${root_dir}/${files_to_process}
          done
      done
  fi
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
    if [[ -f "${GRAFANA_CFG_PLUGINS}" ]]
    then
        while read -r pluginid pluginversion
        do
            if [[ -n "${pluginid}" ]]
            then
                echo "Installing ${pluginid} ${pluginversion} ..."
                grafana-cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install ${pluginid} ${pluginversion}
            fi
        done <<<$(grep -v '^#' "${GRAFANA_CFG_PLUGINS}")
    fi
}

run_sql_proxies() {
    local instance
    local dbname

    if [[ -d ${AUTH_ROOT} ]]
    then
        for filename in $(find ${AUTH_ROOT} -name '*.proxy')
        do
            dbname=$(basename "${filename}" | sed -n 's/^\(.*\)\.proxy$/\1/p')
            instance=$(head "${filename}")
            echo "Launching local sql proxy for instance ${instance} ..."
            launch cloud_sql_proxy -verbose \
                  -instances="${instance}" \
                  -credential_file="${AUTH_ROOT}/${dbname}-auth.json" \
                  -term_timeout=30s -ip_address_types=PRIVATE,PUBLIC
        done
    fi
}

run_grafana_server() {
    echo "Launching grafana server ..."
    pushd "${GRAFANA_ROOT}" >/dev/null
        if [[ -f "${GRAFANA_CFG_INI}" ]]
        then
            launch grafana-server -config=${GRAFANA_CFG_INI}
        else
            launch grafana-server
        fi
    popd
}

set_homedashboard() {
    local dashboard_httpcode=()
    local dashboard_id

    readarray -t dashboard_httpcode <<<$(
        curl -s -w "\n%{response_code}\n" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "http://127.0.0.1:${PORT}/api/dashboards/uid/${HOME_DASHBOARD_UID}" \
    )
    if [[ "${dashboard_httpcode[1]}" -eq 200 ]]
    then
        dashboard_id=$(jq '.dashboard.id' <<<"${dashboard_httpcode[0]}")
        output=$(curl -s -X PUT -u "${ADMIN_USER}:${ADMIN_PASS}" \
                 -H 'Content-Type: application/json;charset=UTF-8' \
                 -H "X-Grafana-Org-Id: ${HOME_ORG_ID}" \
                 --data-binary "{\"homeDashboardId\": ${dashboard_id}}" \
                 "http://127.0.0.1:${PORT}/api/org/preferences")
        echo "Defined default home dashboard id ${dashboard_id} for org ${HOME_ORG_ID}: ${output}"
    elif [[ "${dashboard_httpcode[1]}" -eq 404 ]]
    then
        echo "No default home dashboard for org ${HOME_ORG_ID} has been found"
    else
        echo "Error setting default HOME dashboard: ${dashboard_httpcode[0]}"
    fi

}

set_users() {
    if [[ -d "${GRAFANA_USER_CONFIG_ROOT}" ]]
    then
        for user_config_file in "${GRAFANA_USER_CONFIG_ROOT}/*.yml"
        do
            for user in  $(yq eval -o=j -I=0 '.users[]' ${user_config_file})
            do
                name=$(eval "echo $(echo $user | jq '.name')")
                login=$(eval "echo $(echo $user | jq '.login')")
                password=$(eval "echo $(echo $user | jq '.password')")
                email=$(eval "echo $(echo $user | jq '.email')")
                orgId=$(eval "echo $(echo $user | jq '.orgId')")
                role=$(eval "echo $(echo $user | jq '.role')")

                echo "Add user - name: ${name}, login: ${login}, email: ${email}, orgId: ${orgId}"
                curl -s -H "Content-Type: application/json" \
                     -u "${ADMIN_USER}:${ADMIN_PASS}" \
                    -XPOST "http://127.0.0.1:${PORT}/api/admin/users" \
                    -d @- <<EOF
{
    "name":"${name}",
    "login":"${login}",
    "password":"${password}",
    "email":"${email}",
    "orgId":${orgId}
}
EOF

                echo "Associate user ${login} with org ${orgId} and role ${role}"
                curl -s -H "Content-Type: application/json" \
                     -u "${ADMIN_USER}:${ADMIN_PASS}" \
                    -XPOST "http://127.0.0.1:${PORT}/api/orgs/${orgId}/users" \
                    -d @- <<EOF
{
    "loginOrEmail":"${login}",
    "role":"${role}"
}
EOF
            done
        done
    fi
}

configure_post_startup() {
    local counter=30
    local status=0

    while [[ ${counter} -gt 0 ]]
    do
        if status=$(curl -s -o /dev/null -w '%{http_code}' \
                -u "${ADMIN_USER}:${ADMIN_PASS}" \
                -H "X-Grafana-Org-Id: ${HOME_ORG_ID}" \
                "http://127.0.0.1:${PORT}/api/org/preferences")
        then
            [[ ${status} -eq 200 ]] && break
        fi
        sleep 2
        counter=$((counter - 1))
    done
    if [[ ${status} -eq 200 ]]
    then
        set_users
        set_homedashboard
    else
        echo "Error setting querying preferences to determine grafana application startup: ${status}"
    fi
}

################################################################################

generate_alerts_from_templates
pre-process ${GRAFANA_DASHBOARD_ROOT}
pre-process ${GRAFANA_ALERTING_ROOT}
set_sql_databases
set_seed_secrets
set_datasources

# Run
install_grafana_plugins
run_sql_proxies
run_grafana_server &
# Set home dashboard only on the first instance
[[ "${CF_INSTANCE_INDEX:-0}" == "0" ]] && configure_post_startup
# Go back to grafana_server and keep waiting, exit whit its exit code
wait

