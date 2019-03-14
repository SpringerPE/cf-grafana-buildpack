#!/usr/bin/env bash

export DOMAIN=$(echo ${VCAP_APPLICATION} | jq ".[\"uris\"][0]" --raw-output)

export GRAFANA_ROOT=/home/vcap/deps/grafana
export SQLPROXY_ROOT=/home/vcap/deps/cloud_sql_proxy
export APP_ROOT=${HOME}
export PATH=${PATH}:${GRAFANA_ROOT}/bin:${SQLPROXY_ROOT}

###

randomstring() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
}

# exec grafana and create the datasources
launch() {
    local backgroud=${1}
    shift
    echo "Launching: '$@'"
    # Exec process
    echo "* -- START -- PID=$$"
    (
        echo "* Process environment was:"
        echo "* Command line of pid $$ was:"
        echo "$@"
        echo "* -- $(date) --"
        {
            exec $@  2>&1;
        }
    ) &
    pid=$!
    sleep 30
    if ! ps -p $pid >/dev/null 2>&1; then
        echo
        echo "Error launching '$@'."
        rvalue=1
    else
        if [[ -z "${background}" ]] && [[ "${background}" == "bg" ]]
        then
            wait $pid 2>/dev/null
            rvalue=$?
        else
            rvalue=0
        fi
    fi
    echo "* -- END -- RC=$rvalue"
    return $rvalue
}


echo "Setting environment variables ..."
if [[ -z "${SECRET_KEY}" ]]
then
    export SECRET_KEY=$(randomstring)
    echo "######################################################################"
    echo "WARNING: SECRET_KEY environment variable not defined!"
    echo "Used for signing some datasource settings like secrets and passwords."
    echo "Cannot be changed without requiring an update to datasource settings to re-encode them."
    echo "Please define it in grafana.ini or using an environment variable!"
    echo "Generated SECRET_KEY=${SECRET_KEY}"
    echo "######################################################################"
fi
export ADMIN_USER=${ADMIN_USER:-admin}
export ADMIN_PASS=${ADMIN_PASS:-admin}
export EMAIL=${EMAIL:-grafana@$DOMAIN}


echo "Launching local sql proxy ..."
if [ -f "${APP_ROOT}/auth.json" ]
then
    launch fg cloud_sql_proxy -instances=sn-paas-sb-gcp:europe-west4:pcf-sb-1-1552482443106534027=tcp:3306 -credential_file "${APP_ROOT}/auth.json" -log_debug_stdout -verbose
fi


echo "Launching grafana server..."
cd ${GRAFANA_ROOT}
if [ -f "${APP_ROOT}/grafana.ini" ]
then
    launch bg grafana-server -config=${APP_ROOT}/grafana.ini
else
    launch bg grafana-server
fi
