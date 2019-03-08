#!/usr/bin/env bash

export GRAFANA_ROOT=/var/vcap/deps/grafana
export APP_ROOT=${HOME}
export DOMAIN=$(echo ${VCAP_APPLICATION} | jq ".[\"uris\"][0]" --raw-output)
export PATH=$PATH:${GRAFANA_ROOT}/bin


# exec grafana and create the datasources
launch() {
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
        wait $pid 2>/dev/null
        rvalue=$?
    fi
    echo "* -- END -- RC=$rvalue"
    return $rvalue
}


cd ${GRAFANA_ROOT}

echo "Launching grafana server..."
if [ -f "${APP_ROOT}/grafana.ini" ]
then
    launch ./bin/grafana-server -config=${APP_ROOT}/grafana.ini
else
    launch ./bin/grafana-server
fi

