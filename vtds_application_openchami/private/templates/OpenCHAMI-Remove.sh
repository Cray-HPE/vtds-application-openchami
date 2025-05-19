#! /usr/bin/bash
set -eu -o pipefail
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
       down --volumes
