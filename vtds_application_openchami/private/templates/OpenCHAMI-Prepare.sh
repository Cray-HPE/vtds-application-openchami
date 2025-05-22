#! /usr/bin/bash
#
# MIT License
#
# (C) Copyright 2025 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
set -eu -o pipefail

usage() {
    echo $* >&2
    echo "usage: OpenCHAMI-Prepare.sh <host-ip-addr>" >&2
    exit 1
}

fail() {
    echo $* >&2
    exit 1
}

computes() {
    cat <<EOF
services:
  rf-x0c0s1b0:
    container_name: rf-x0c0s1b0
    hostname: x0c0s1b0
    image: ghcr.io/openchami/csm-rie:latest
    environment:
      - MOCKUPFOLDER=EX235a
      - MAC_SCHEMA=Mountain
      - XNAME=x0c0s1b0
      - PORT=443
    networks:
      internal:
        aliases:
          - x0c0s1b0
  rf-x0c0s2b0:
    container_name: rf-x0c0s2b0
    hostname: x0c0s2b0
    image: ghcr.io/openchami/csm-rie:latest
    environment:
      - MOCKUPFOLDER=EX235a
      - MAC_SCHEMA=Mountain
      - XNAME=x0c0s2b0
      - PORT=443
    networks:
      internal:
        aliases:
          - x0c0s2b0
  rf-x0c0s3b0:
    container_name: rf-x0c0s3b0
    hostname: x0c0s3b0
    image: ghcr.io/openchami/csm-rie:latest
    environment:
      - MOCKUPFOLDER=EX235a
      - MAC_SCHEMA=Mountain
      - XNAME=x0c0s3b0
      - PORT=443
    networks:
      internal:
        aliases:
          - x0c0s3b0
  rf-x0c0s4b0:
    container_name: rf-x0c0s4b0
    hostname: x0c0s4b0
    image: ghcr.io/openchami/csm-rie:latest
    environment:
      - MOCKUPFOLDER=EX235a
      - MAC_SCHEMA=Mountain
      - XNAME=x0c0s4b0
      - PORT=443
    networks:
      internal:
        aliases:
          - x0c0s4b0
EOF
}

internal_network_fix() {
cat <<EOF
networks:
{% for network in discovery_networks %}
  {{ network.name }}:
    ipam:
      driver: default
      config:
        - subnet: {{ network.cidr }}
{% endfor %}
EOF
}

magellan_discovery() {
cat <<EOF
services:
  magellan-discovery:
    image: magellan-discovery:latest
    container_name: magellan-discovery
    hostname: magellan-discovery
    environment: []
    depends_on:
      smd:
        condition: service_healthy
      opaal:
        condition: service_healthy
    networks:
      - internal
    entrypoint:
      - /magellan_discovery.sh
EOF
}

prepare_package_management() {
    dnf -y check-update || true
    dnf -y config-manager \
        --add-repo https://download.docker.com/linux/centos/docker-ce.repo \
        || fail "unable to add docker package repo to dnf"
}

install_docker() {
    dnf -y install docker-ce docker-ce-cli containerd.io git || true
}

start_docker() {
    systemctl start docker || fail "unable to start docker"
    systemctl enable docker || fail "unable to enable docker"
}

update_hosts() {
    host_ip="${1}"; shift || fail "update_hosts called without host IP"
    if ! grep 'foobar.openchami.cluster' /etc/hosts; then
        echo "${host_ip}" foobar.openchami.cluster >> /etc/hosts
    fi
}

set_up_openchami() {
    host_ip="${1}"; shift || fail "set_up_openchami called without host IP"
    rm -rf /root/deployment-recipes || \
        fail "can't remove /root/deployment_recipes"
    git clone https://github.com/OpenCHAMI/deployment-recipes.git \
        /root/deployment-recipes || \
        fail "can't retrieve deployment recipes from github"
    cd /root/deployment-recipes/quickstart || \
        fail "can't change directory to /root/deployment_recipes/quickstart"
    ./generate-configs.sh -f || fail "generating quickstart configs failed"
    sed -i -e "s/LOCAL_IP=.*$/LOCAL_IP=${host_ip}/" .env
    computes > computes.yml || \
        fail "can't create 'computes' docker compose script"
    internal_network_fix > internal_network_fix.yml || \
        fail "can't create 'internal_network_fix.yml' docker compose script"
    magellan_discovery > magellan_discovery.yml || \
        fail "can't create 'magellan_discovery.yml' docker compose script"
}

OCHAMI_HOST_IP="${1}"; shift || usage "no node type specified"
prepare_package_management
install_docker
start_docker
update_hosts "${OCHAMI_HOST_IP}"
set_up_openchami "${OCHAMI_HOST_IP}"
