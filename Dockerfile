FROM cloudfoundry/cflinuxfs3
copy . /home/buildpack/
run  /home/buildpack/test/staging.sh
volume /home/vcap/app
workdir /home/vcap/app

env CF_INSTANCE_INDEX=0
env CF_INSTANCE_IP=127.0.0.1
env CF_INSTANCE_GUID=6c94b3cc-6759-4e56-74d9-c743
env INSTANCE_INDEX=0
env TMPDIR=/home/vcap/tmp
env HOME=/home/vcap/app

CMD /home/buildpack/test/run.sh