#!/bin/bash
# This is a quick test which (I guess) only runs in linux. We would need to
# create a proper container (Base cflinuxfs3) for proper testing
cd  /home/buildpack

mkdir -p /home/vcap/app /home/vcap/cache /home/vcap/deps/0 /home/vcap/tmp

echo ">> Running detect ..."
./bin/detect /home/vcap/app

echo ">> Running supply ..."
./bin/supply /home/vcap/app /home/vcap/cache /home/vcap/deps 0

echo ">> Running finalize ..."
./bin/finalize /home/vcap/app /home/vcap/cache /home/vcap/deps 0

echo ">> Running release ..."
./bin/release /home/vcap/app




