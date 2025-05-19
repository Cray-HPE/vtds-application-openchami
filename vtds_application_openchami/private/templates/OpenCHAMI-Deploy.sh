#! /usr/bin/bash
set -e -o pipefail
cd /root
docker build -t magellan-discovery:latest -f magellan_discovery_dockerfile /root
cd /root/deployment-recipes/quickstart
docker compose \
       -f base.yml \
       -f internal_network_fix.yml \
       -f postgres.yml \
       -f jwt-security.yml \
       -f haproxy-api-gateway.yml \
       -f openchami-svcs.yml \
       -f autocert.yml \
       -f coredhcp.yml \
       -f configurator.yml \
       -f computes.yml \
       -f magellan-discovery.yml \
       up -d
source bash_functions.sh
get_ca_cert > cacert.pem
ACCESS_TOKEN=$(gen_access_token)
curl \
    --cacert cacert.pem \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://foobar.openchami.cluster:8443/hsm/v2/State/Components | jq
