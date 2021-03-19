#!/bin/bash

cp -rv  /home/stage/. /home/vcap/app

for script in /home/vcap/app/.profile.d/*
do
   source ${script}
done

echo "Running simulated app..."
./.grafana.sh

while true
do
    sleep 60
    if ! curl -fs http://localhost:${PORT}/  > /dev/null
    then
      echo "HealthCheck failed"
      exit 1
    fi
done