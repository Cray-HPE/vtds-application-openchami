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

function find_if_by_cidr() {
    addr=${1}; shift || fail "no CIDR supplied when looking up ip interface"
    ip --json a | \
        jq -r "\
          .[] | .ifname as \$ifname | \
          .addr_info | .[] | \
              select( .family == \"inet\") | \
              select( (.local + \"/\" + ( .prefixlen | tostring)) == \"${addr}\" ) | \
              \"\(\$ifname)\" \
        "
}

# Find the interface on which NAT is running and the 

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
{% for network in discovery_networks %}
{% if network.external %}
htpasswd -B -b -c /etc/sushy-emulator/users \
         {{ network.redfish_username }} \
         {{ network.redfish_password }}
{% endif %}
{% endfor %}

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
NAT_CIDR="{{ hosting_config.management.nat_if_cidr }}"
NAT_ADDR="$(echo "${NAT_CIDR}" | cut -d / -f 1)"
NAT_IF="$(find_if_by_cidr "${NAT_CIDR}")"
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
