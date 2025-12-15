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
set -e -o pipefail
function error_handler() {
    local filename="${1}"; shift
    local lineno="${1}"; shift
    local exitval="${1}"; shift
    echo "exiting on error [${exitval}] from ${filename}:${lineno}" >&2
    exit ${exitval}
}
trap 'error_handler "${BASH_SOURCE[0]}" "${LINENO}" "${?}"' ERR

function fail() {
    local message="${*:-"failing for no specified reason"}"
    echo "${BASH_SOURCE[1]}:${BASH_LINENO[0]}:[${FUNCNAME[1]}]: ${message}" >&2
    return 1
}

function usage() {
    local msg="{$*}"
    if [ -n "${msg}" ]; then
        echo "${msg}" >&2
    fi
    echo "Usage: prepare_blade.sh <blade-class> <blade-instance>" >&2
    exit 1
}

# Pick off the blade class and instance from the arguments
BLADE_CLASS=${1}; shift || usage "missing blade class parameter"
BLADE_INSTANCE=${1}; shift || usage "missing blade instance parameter"

# These files need to have their copyright comments stripped from them
# because the comments break parsing.
STRIP_COMMENT_FILES=(
    "bmc_info.json"
)

function find_if_by_addr() {
    addr=${1}; shift || fail "no ip addr supplied when looking up ip interface"
    ip --json a | \
        jq -r "\
          .[] | .ifname as \$ifname | \
          .addr_info | .[] | \
              select( .family == \"inet\") | \
              select( (.local) == \"${addr}\" ) | \
              \"\(\$ifname)\" \
        "
}

function rf_username() {
    local blade_class="${1}"; shift || fail "missing blade class in rf_username"
    local blade_instance="${1}"; shift || fail "missing blade instance in rf_username"
    sudo cat /etc/vtds/bmc_info.json | \
        jq -r "\
          .[] | \
          select(
            .blade_class == \"${blade_class}\" and \
            .blade_instance == \"${blade_instance}\" \
          ) |
          .redfish_username \
        "
}

function rf_password() {
    blade_class="${1}"; shift || fail "missing blade class in rf_password"
    blade_instance="${1}"; shift || fail "missing blade instance in rf_password"
    sudo cat /etc/vtds/bmc_info.json | \
        jq -r "\
          .[] | \
          select(
            .blade_class == \"${blade_class}\" and \
            .blade_instance == \"${blade_instance}\" \
          ) |
          .redfish_password \
        "
}

# Strip comments out of prepared data files as needed.
for file in "${STRIP_COMMENT_FILES[@]}"; do
    sed -i \
        -e "/^[[:blank:]]*#/d" \
        -e "s/[[:blank:]]*#.*$//" \
        "${file}"
done

# Copy the BMC information into /etc/vtds and make sure it is not
# publicly readable since it contains RedFish passwords for BMCs.
chmod 600 bmc_info.json
chown root:root bmc_info.json
mkdir -p /etc/vtds
cp bmc_info.json /etc/vtds/bmc_info.json
chmod 600 /etc/vtds/bmc_info.json
chown root:root /etc/vtds/bmc_info.json

# Create the directory in /etc where all of the Sushy Tools setup will
# go.
mkdir -p /etc/sushy-emulator
chmod 700 /etc/sushy-emulator

# Make self-signed X509 cert / key for the sushy-emulator
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout /etc/sushy-emulator/key.pem \
        -out /etc/sushy-emulator/cert.pem \
        -subj "/C=US/ST=SushyTools/L=Vtds/O=vTDS/CN=vtds"

# Create an htpasswd file for the sushy-emulator to use
rf_password "${BLADE_CLASS}" "${BLADE_INSTANCE}" | \
    htpasswd -B -i -c /etc/sushy-emulator/users \
             "$(rf_username ${BLADE_CLASS} ${BLADE_INSTANCE})"

# Put the nginx HTTPS reverse proxy configuration into
# the nginx configuration directory
cp /root/nginx-default-site-config /etc/nginx/sites-available/default

# Put the sushy-emulator config away where it belongs...
cp /root/sushy-emulator.conf /etc/sushy-emulator/config

# Put the systemd unit file for sushy-emulator where it belongs
cp /root/sushy-emulator.service /etc/systemd/system/sushy-emulator.service

# Start up the sushy-emulator
systemctl daemon-reload
systemctl enable --now sushy-emulator
systemctl enable --now nginx

{%- if hosting_config is defined %}
# Set up an alternative hosts file just for OpenCHAMI that dnsMasq
# will serve OpenCHAMI host info from.
cat <<EOF > /etc/hosts_openchami
{{ hosting_config.management.net_head_ip }} {{ hosting_config.management.net_head_fqdn }}
EOF

# Set up dnsmasq with the FQDN of the cluster head node (management
# node) presented on the management network.
if ip address | grep {{ hosting_config.management.net_head_dns_server }}; then
    cat <<EOF > /etc/dnsmasq.conf
# Serving DNS on port 53
port=53
# Forward unresolved requests to the GCP metadata / DNS server
server={{ hosting_config.management.upstream_dns_server }}
# Listen on the management network and on localhost
listen-address={{ hosting_config.management.net_head_dns_server }}
listen-address=127.0.0.1
# Don't serve /etc/hosts because that has addresses that most other nodes
# can't reach.
no-hosts
# Serve the OpenCHAMI hosts instead.
addn-hosts=/etc/hosts_openchami
EOF
systemctl enable --now dnsmasq
fi
{%- endif %}

# Set up NAT on the blade's public IP if this is the NAT blade
# (i.e. the blade hosting the management node)
NAT_ADDR="{{ hosting_config.management.nat_if_ip_addr }}"
NAT_IF="$(find_if_by_addr "${NAT_ADDR}")"
CLUSTER_CIDR="{{ hosting_config.management.cluster_net_cidr }}"
if [[ "${NAT_IF}" != "" ]]; then
    nft flush ruleset
    nft add table nat
    nft 'add chain nat postrouting { type nat hook postrouting priority 100 ; }'
    nft add rule nat postrouting ip \
        saddr ${CLUSTER_CIDR} \
        oif ${NAT_IF} \
        snat to ${NAT_ADDR}
    nft add rule nat postrouting masquerade
fi
