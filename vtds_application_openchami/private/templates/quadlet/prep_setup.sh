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

# Set up the system level pieces needed to start deploying
# OpenCHAMI. This script is intended to be run by a user with
# passwordless 'sudo' permissions. The base node preparation script
# sets up the user 'rocky' with that before chaining here.

# Common setup for the prepare node scripts
set -o errexit -o errtrace
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

function discovery_version() {
    # The version of SMD changed how ochami needs to feed it manually
    # discovered node data at 2.19. We need an extra option to address
    # that if the version is 2.18 or lower.
    local major=""
    local minor=""
    local patch=""
    IFS='.' read major minor patch < \
       <( \
          sudo podman ps | \
              grep '/smd:v' | \
              awk '{sub(/^.*:v/, "", $2); print $2 }'\
       )
    if [ "${major}" -le "2" -a "${minor}" -lt "19" ]; then
       echo "--discovery-version=1"
    fi
}

function node_groups() {
    # Templated mechamism for getting a list of unique node 'group'
    # names from the list of managed nodes.
    sort -u <<EOF
{%- for node in nodes %}
{{ node.node_group }}
{%- endfor %}
EOF
}

function managed_macs() {
    cat <<EOF
{%- for mac in managed_macs %}
{{ mac }}
{%- endfor %}
EOF
}

function switch_dns() {
    # This function uses nmcli to find and remove all nameservers from
    # the current configuration and then to add back only the local
    # management network IP as a nameserver on the management
    # network. It is complicated because nmcli is complicated...
    #
    # First, get the list of connections (interfaces) with nameservers
    # assigned to them...
    local nameserver="${1}"; shift || fail "no nameserver specified to switch to"
    local domain="${1}"; shift || fail "no search domain specified"
    # Optional network argument tells the logic to place the
    # nameserver on the connection containing a local network address
    # but not the nameserver address. If it is not provided the
    # nameserver address is used.
    local network="${1:-"${nameserver}"}"
    local connection=""
    local connections="$(
        for connection in $(nmcli --terse --fields NAME connection show); do
            echo -n "${connection} "
            nmcli connection show "${connection}" | grep ipv4.dns:
        done | grep -v '[-]-' | cut -d ' ' -f 1
    )"

    # Now, strip off the nameserver from each of the affected connections...
    for connection in ${connections}; do
        sudo nmcli connection modify "${connection}" ipv4.dns "" && \
            sudo nmcli connection down "${connection}" && \
            sudo nmcli connection up "${connection}"
    done

    # Okay, now, find the connection that has an IP address that
    # matches the internal IP address of the head-node on the
    # management network (in other words, the connection that is the
    # management network)
    connection="$(
        for connection in $(nmcli --terse --fields NAME connection show); do
            echo -n "${connection} "
            nmcli connection show "${connection}" | grep 'ipv4.addresses:'
        done | grep -F "${network}" | cut -d ' ' -f 1
    )"
    [[ "${connection}" =~ ^[^\ ]*$ ]] || fail "more than one interface [${connection}] has the requested local network address '${network}'"
    [[ "${connection}" != "" ]] || fail "no iinterface found with a suitable network to configure the DNS server '${nameserver}'"

    # Set the nameserver on the connection and put the cluster domain
    # in the search on the same connection
    sudo nmcli connection modify "${connection}" ipv4.dns "${nameserver}" && \
        sudo nmcli connection modify "${connection}" ipv4.dns-search "${domain}" && \
        sudo nmcli connection down "${connection}" && \
        sudo nmcli connection up "${connection}"
}

function patch_coredns() {
    local replacement="Volume=/etc/openchami/configs/Corefile:/Corefile:ro,Z"
    sudo sed -i \
         -e "/^Volume=.*Corefile$/s--${replacement}-" \
         /etc/containers/systemd/coresmd-coredns.container
}

# Some useful variables that can be templated
MANAGEMENT_HEADNODE_FQDN="{{ hosting_config.management.net_head_fqdn }}"
CLUSTER_DOMAIN="{{ hosting_config.management.net_head_domain }}"
MANAGEMENT_HEADNODE_IP="{{ hosting_config.management.net_head_ip }}"
MANAGEMENT_NET_LENGTH="{{ hosting_config.management.prefix_len }}"
MANAGEMENT_NET_MASK="{{ hosting_config.management.netmask }}"
MANAGEMENT_EXT_NAMESERVER="{{ hosting_config.management.net_head_dns_server }}"
MANAGEMENT_NODE_CLASS="{{ host_node_class }}"

{%- if hosting_config.cohost.enable %}
LIBVIRT_NET_IP="{{ hosting_config.cohost.net_head_ip }}"
LIBVIRT_NET_LENGTH="{{ hosting_config.cohost.prefix_len }}"
LIBVIRT_NET_MASK="{{ hosting_config.cohost.netmask }}"
{%- endif %}

