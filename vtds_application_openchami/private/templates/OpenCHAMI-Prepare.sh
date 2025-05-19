#! /usr/bin/bash
set -eu -o pipefail
dnf -y check-update || true
dnf -y config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io git || true
systemctl start docker
systemctl enable docker
if ! grep 'foobar.openchami.cluster' /etc/hosts; then
    echo "10.1.1.10" foobar.openchami.cluster >> /etc/hosts
fi
rm -rf /root/deployment-recipes
git clone https://github.com/OpenCHAMI/deployment-recipes.git /root/deployment-recipes
cd /root/deployment-recipes/quickstart
./generate-configs.sh -f
sed -i -e 's/LOCAL_IP=.*$/LOCAL_IP=10.1.1.10/' .env
cat <<EOF > computes.yml
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
cat <<EOF > internal_network_fix.yml
networks:
  internal:
    ipam:
      driver: default
      config:
        - subnet: 172.25.0.0/24
EOF
cat <<EOF > magellan-discovery.yml
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
