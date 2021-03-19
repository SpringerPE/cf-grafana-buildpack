#!/bin/bash
# This is a quick test which (I guess) only runs in linux. We would need to
# create a proper container (Base cflinuxfs3) for proper testing

# Delete all folders to start fresh
rm -rf /tmp/buildpack/app /tmp/buildpack/deps/0
#rm -rf /tmp/buildpack/cache
mkdir -p /tmp/buildpack/app /tmp/buildpack/cache /tmp/buildpack/deps/0

echo ">> Running detect ..."
./bin/detect /tmp/buildpack/app

echo ">> Running supply ..."
./bin/supply /tmp/buildpack/app /tmp/buildpack/cache /tmp/buildpack/deps 0

echo ">> Running simulated app ..."
# From here, simulate running in a diego container (vector.sh)
export ROOT=/tmp/buildpack/app
export PATH=$PATH:/tmp/buildpack/deps/0/vector/bin
rm -rf /tmp/buildpack/app/vector

# Define variables here like in the manifest
export DEBUG=1
# No log destination, in order to force debug only

# run redirector
. $ROOT/.grafana.sh
set +x

# App running logs
echo app starting 
echo app error log >&2
echo app running
for ((i=60; i>=1; i--))
do
    echo "My app is sending app log $i"
    sleep 1
done



