#!/bin/bash
# This is a quick test which (I guess) only runs in linux. We would need to
# create a proper container (Base cflinuxfs3) for proper testing
cd  /home/buildpack

mkdir -p /home/stage /home/vcap/cache /home/vcap/deps/0 /home/vcap/tmp

echo ">> Running detect ..."
./bin/detect /home/stage

echo ">> Running supply ..."
./bin/supply /home/stage /home/vcap/cache /home/vcap/deps 0

echo ">> Running finalize ..."
./bin/finalize /home/stage /home/vcap/cache /home/vcap/deps 0

echo ">> Running release ..."
./bin/release /home/stage




