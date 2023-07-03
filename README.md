# cf-grafana-buildpack

Cloudfoundry buildpack to deploy Grafana 9 and get it automatically configured.
This buildpack is able to automatically setup a database from a service broker
instance (both mysql and postgres are supported) if no database connection is provided
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

**In order to test new versions of the buildpack, please use `dev` branch** and
merge with master only when you are sure it works, otherwise it would cause
a lot of pain to other users of this buildpack.

## Using it

First of all, this buildpack has no requirements at all, in order to get Grafana working,
you can create app folder, put a `manifest.yml` like this in your root folder: 

```manifest.yml
---
applications:
- name: grafana
  memory: 512M
  instances: 1
  stack: cflinuxfs4
  random-route: true
  buildpacks:
  - https://github.com/SpringerPE/cf-grafana-buildpack.git
  env:
    ADMIN_USER: admin
    ADMIN_PASS: admin
    SECRET_KEY: yUeEBtX7eTmh2ixzz0oHsNyyxYmebSat
```

and run from the root folder `cf push`

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

* The app folder is the `provisioning` folder [specified in the documentation](https://grafana.com/docs/grafana/latest/administration/provisioning/), so you can create these directories: `datasources`, `dashboards`, `notifiers` there as the official documenation says.
* The default configuration refereed as `defaults.ini` is provided and customized for the buildpack: https://github.com/SpringerPE/cf-grafana-buildpack/blob/master/defaults.ini
* The custom configuration file referred as `custom.ini` will be applied automatically by placing a file named `grafana.ini` in the root folder of the app, so `custom.ini` is called `grafana.ini`.
* You can use all environment variables to setup Grafana (`GF_*`), except the ones in the `[paths]` section of the configuration file.
* Plugins folder points to `plugins` in the root app, so all plugins will be installed there automatically.

#### Important environment variables

Apart of the Grafana environment variables, you can define these ones:

* **DEFAULT_DATASOURCE_EDITABLE** (default `false`). By default the auto-generated datasources for Prometheus and Alertmanager are not editable. Changing this value makes then editable, but if you do not use a DB be aware that changes on their properties will be lost after redeploy grafana.
* **DEFAULT_DATASOURCE_TIMEINTERVAL** (default `60s`). Lowest interval/step value that should be used for default generated data source.
* **HOME_DASHBOARD_UID** (default `home`). Used to setup automatically the Grafana home dashboard (the one users see automatically when they log in). If you provision a dashboard with `uid`  equal to `HOME_DASHBOARD_UID`, the buildpack will setup such dashboard as home. The `uid` is part of the url of each dashboard, and it can be defined to a string like `home` (by default is a random generated string) to give some meaning to the dashboard urls. More info: https://grafana.com/docs/http_api/dashboard/#identifier-id-vs-unique-identifier-uid.
* **ADMIN_USER**: main admin user (default is `admin`)
* **ADMIN_PASS**: admin password (defautl is `admin`)
* **SECRET_KEY**: Used for signing some datasource settings like secrets and passwords. Cannot be changed without requiring an update to datasource settings to re-encode them. Because this variable is so important, if it is not defined, **it defaults to the space uuid** where the app is running.
* **DOMAIN**: uri of the application, defauls to the first route in CF.
* **EMAIL**: when a smtp is configured this is the `from` field, defaults to `grafana@$DOMAIN`.
* **DB_BINDING_NAME**: name of the binding with a service instance to use as SQL database. By default is empty, so the builpack will search for bindings providing a DB connection string in their `credentials.uri` field. If it is defined it will skip automatic search and focus only on the provided one.
* **URL**: URL of the app, defaults to `http://$DOMAIN`. If using https you will need to redefine this variable (specially for Oauth integrations!).

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
(check `parameters.sh`), example:

```runtime.txt
# Define your grafana version here
9.3.1
```

This buildpack only supports Grafana 7.x or greater!

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


# Using Oauth

For example, to define Oauth auth with Google, just create a file `grafana.ini` like this:
```
[auth.google]
enabled = true
client_id = "${CLIENT_ID}"
client_secret = "${CLIENT_SECRET}"
scopes = https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email
auth_url = https://accounts.google.com/o/oauth2/auth
token_url = https://accounts.google.com/o/oauth2/token
allowed_domains = companydomain1.com companydomain2.com
allow_sign_up = true
```

In the CF manifest, you can define the variables needed:
```
---
applications:
- name: mission-control
  memory: 512M
  instances: 1
  stack: cflinuxfs4
  buildpack: https://github.com/SpringerPE/cf-grafana-buildpack.git
  env:
    CLIENT_ID:  'blabla'
    CLIENT_SECRET: 'blabla'
    URL: https://mygrafana.companydomain.com
```

Do not forget to define `$URL` with the https protocol!.


# Development

In order to test new versions of the buildpack, use `docker-compose build && docker-compose up`
Please use  a different  branch and merge with master only when you are sure it works, otherwise it would cause
a lot of pain to other users of this buildpack.

Implemented using bash scripts to make it easy to understand and change.

https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html

The builpack uses the `deps` and `cache` folders according the implementation purposes,
so, the first time the buildpack is used it will download all resources, next times 
it will use the cached resources.

# Author

Copyright © Springer Nature

MIT License
