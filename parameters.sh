# Variables, this file is designed to be sourced by supply

# default versions
GRAFANA_VERSION="${GRAFANA_VERSION:-9.3.1}"
CLOUDSQL_PROXY_VERSION="${CLOUDSQL_PROXY_VERSION:-1.32.0}"
YQ_VERSION="${YQ_VERSION:-4.30.5}"
GRAFANA_ALERTMANAGER_VERSION="${GRAFANA_ALERTMANAGER_VERSION:-1.2.1}"

# Download URLS
GRAFANA_DOWNLOAD_URL="https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz"
CLOUDSQL_PROXY_DOWNLOAD_URL="https://storage.googleapis.com/cloudsql-proxy/v${CLOUDSQL_PROXY_VERSION}/cloud_sql_proxy.linux.amd64"

# dependencies paths
GRAFANA_DIR="${DEPS_DIR}/${DEPS_IDX}/grafana"
SQLPROXY_DIR="${DEPS_DIR}/${DEPS_IDX}/cloud_sql_proxy"
YQ_DIR="${DEPS_DIR}/${DEPS_IDX}/yq"

GRAFANA_MIN_VERSION="7.0.0"