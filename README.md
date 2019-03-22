# cf-grafana-buildpack

Cloudfoundry buildpack to deploy grafana 6 and get it automatically configured.
This buildpack is able to automatically setup a database from a service broker
instance (bot mysql and postgres are supported) if no database connection is provided
it will use a sqlite database.

When you can skip having a proper DB (mysql or postgres):

1. If a single grafana instance is enough for your use case.
2. If you do not care about user management
3. If all dashboards and datasources are defined in configuration files.

With points 2 and 3 potentially you would have skip 1'st point and have multiple instances,
but this setup is not tested.

Having mysql or postgres, this buildpack allows you to deploy multiple instances because
sessions are stored there.

This buildpack is focused on CloudSQL offered by Google Service Broker. It "should" support
other service broker instances, but we have not checked it (PR are welcome!)


## Using it

First of all, this buildpack has no requirements at all, in order to get Grafana working,
you can create app folder, put a `manifest.yml` like this: 

```manifest.yml
---
applications:
- name: grafana
  memory: 512M
  instances: 1
  stack: cflinuxfs3
  random-route: true
  buildpack: https://github.com/SpringerPE/cf-grafana-buildpack.git
  env:
    ADMIN_USER: admin
    ADMIN_PASS: admin
    SECRET_KEY: yUeEBtX7eTmh2ixzz0oHsNyyxYmebSat
```

and run `cf push`

Aditionally by binding the app to a SQL instance (mysql or postgres), 
everything will be saved in a persistent DB, but this is not really 
recommented unless you are testing or you want to become a good 
developer/devops (you know replicable builds, traceable changes, etc)


# Documentation

To use this buildpack, specify the URI of this repository when push to Cloud Foundry.
```
$ cf push <APP-NAME> -b https://github.com/SpringerPE/cf-grafana-buildpack.git
```

If you want to deploy a specific version, have a look at the git tags available
and put a `#` removing the `.git` extension like this:
```
$ cf push <APP-NAME> -b https://github.com/SpringerPE/cf-grafana-buildpack#<TAG>
```

For example:
```
$ cf push <APP-NAME> -b https://github.com/SpringerPE/cf-grafana-buildpack#v1
```

or define it in the `manifest.yml`:

```
---
applications:
- name: grafana
  buildpack: https://github.com/SpringerPE/cf-grafana-buildpack#v1
```

### Configuration

First have a look at the official documentation of Grafana: http://docs.grafana.org/installation/configuration/

This buildpack is highly flexible, these are some keypoints to match the official documentation with this buildpack implementation.

* The app folder is the `provisioning` folder specified in the documentation, so you can create these directories: `datasources`, `dashboards`, `notifiers` there as the official documenation says.
* The default configuration refereed as `defaults.ini` is provided and customized for the buildpack: https://github.com/SpringerPE/cf-grafana-buildpack/blob/master/defaults.ini
* The custom configuration file referred as `custom.ini` will be applied automatically by placing a file named `grafana.ini` in the root folder of the app, so `custom.ini` is called `grafana.ini`.
* You can use all environment variables to setup Grafana (`GF_*`), except the ones in the `[paths]` section of the configuration file.
* Plugins folder points to `plugins` in the root app, so all plugins will be installed there automatically.

#### Important environment variables

Apart of the Grafana environment variables, you can define these ones:

* **ADMIN_USER**: main admin user, default is `admin`)
* **ADMIN_PASS**: admin password, defautl is `admin`)
* **SECRET_KEY**: Used for signing some datasource settings like secrets and passwords. Cannot be changed without requiring an update to datasource settings to re-encode them. Because this variable is so important, if it is not defined, **it defaults to the space uuid** where the app is running.
* **DOMAIN**: uri of the application, defauls to the first route in CF.
* **EMAIL**: when a smtp is configured this is the `from` field, defaults to `grafana@$DOMAIN`.
* **DB_BINDING_NAME**: name of the binding with a service instance to use as SQL database. By default is empty, so the builpack will search for bindings providing a DB connection string in their `credentials.uri` field. If it is defined it will skip automatic search and focus only on the provided one.
* **MAIN_DB_BINDING_NAME**: name of the binding for the SQL service instance to use as main DB: users, dashboards, datasources, ... will be saved there. It is used only as fallback if `DB_BINDING_NAME` is not found/defined, by default its value is `main`.
* **SESSION_DB_BINDING_NAME**: name of the binding for the SQL service instance to use for saving online web sessions. For now this builpack only supports SQL backends, but Grafana also supports other backends as redis or memcached. Used only as fallback if `DB_BINDING_NAME` is not found/defined, by default its value is `session`.

For production use, define a proper `ADMIN_PASS` and `SECRET_KEY`. The rest of variables should
be good with their defautls.

When using a named service broker instance, you can define `MAIN_DB_BINDING_NAME`, otherwise is not needed if the app is bound to only a SQL instance used for everything (sessions, resources, cache)

### Complex configuration

If you want to use your own Grafana settings, just place a `grafana.ini` file in the
app folder with your settings. This is useful to define `oauth` settings and get users
automatically defined in Grafana. Have a look to the official documentation.
 

### Grafana versions and plugins

Grafana version can be specified in a file `runtime.txt`. Lines starting
with `#` are ignored, otherwise it will install the version defined in the buildpack
(check `bin/supply`), example:

```runtime.txt
# Define your grafana version here
6.0.1
```

This buildpack only supports Grafana 6.x!

You can also define which plugins will be automatically installed in a file `plugins.txt`:

```plugins.txt
# Define your plugins here. Format is 2 columns: pluginid version
# https://grafana.com/plugins
satellogic-3d-globe-panel 0.1.0
```

As an alternative you can uncompress a plugin in a `plugins` folder or use locally `grafana-cli`
specifiying `pluginsDir` to `plugins`: `grafana-cli --pluginsDir plugins plugins install <id> <version>`


### Service brokers

As said, you can use a service broker instance which exposes a SQL connection string
in `.credentials.uri`, the DB connection string has to be properly formed and only
using `mysql` or `postgres`.

If you do not have a service broker implementation, you can still use it via user provided
services:

```
$ cf create-user-provided-service mysql-db -p '{"uri":"mysql://root:secret@dbserver.example.com:3306/mydatabase"}'
# bind a service instance to the application
$ cf bind-service <app name> <service name>
# restart the application so the new service is detected
$ cf restart
```

# TLS with GCP Service Broker and Cloud SQL Proxy

This buildpack is primary made to work with GCP Service Broker. Grafana does not support
TLS connection strings for all DBs (e.g. session SQL DB), the way to overcome to this situation
was using a Cloud SQL Proxy: https://github.com/GoogleCloudPlatform/cloudsql-proxy

When the builpack detects a GCP Service broker, it automatically runs the cloud-sql proxy
and change all Grafana connection settings to point to localhost. The SQL proxy connects
to the DB server using the TLS settings and `PrivateData` auth.


# Development

Implemented using bash scripts to make it easy to understand and change.

https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html

The builpack uses the `deps` and `cache` folders according the implementation purposes,
so, the first time the buildpack is used it will download all resources, next times 
it will use the cached resources.


# Author

(c) Jose Riguera Lopez  <jose.riguera@springernature.com>
Springernature Engineering Enablement

MIT License
