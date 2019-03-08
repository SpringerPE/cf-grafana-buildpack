# cf-grafana-buildpack

PoC

# Using it

To use this buildpack, specify the URI of this repository when push to Cloud Foundry.
```
$ cf push <APP-NAME> -b https://github.com/SpringerPE/cf-grafana-buildpack.git
```

# Configuration

http://docs.grafana.org/installation/configuration/

* Using environment variables in the manifest.
* Creating a `grafana.ini` file in the root folder of the app. 
* Root folder of the app is `provisioning` folder, so you can create these directories: `datasources`, `dashboards`, `notifiers`, `plugins`.


# Database support

TODO: Via service brokers


# Author

Jose Riguera
