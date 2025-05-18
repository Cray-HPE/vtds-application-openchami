#! /usr/bin/bash
dnf -y check-update
dnf -y config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io git
systemctl start docker
systemctl enable docker
echo "10.1.1.10" foobar.openchami.cluster >> /etc/hosts
git clone https://github.com/OpenCHAMI/deployment-recipes.git
cd deployment-recipes/quickstart
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
       up -d
source bash_functions.sh
get_ca_cert > cacert.pem
ACCESS_TOKEN=$(gen_access_token)
curl \
    --cacert cacert.pem \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://foobar.openchami.cluster:8443/hsm/v2/State/Components
export COMPOSE_NAME=quickstart
docker run -it --rm --network ${COMPOSE_NAME}_internal ghcr.io/openchami/magellan:latest sh -o vi
