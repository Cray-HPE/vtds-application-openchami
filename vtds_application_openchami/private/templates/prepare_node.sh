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

# The following templated code is set up by the Application layer
# deployment script before shipping this shell script to the node
{% for host in hosts %}
HOST_MACS[{{ host.host_instance }}]={{ host.host_mac }}
{% endfor %}
HOST_NODE_CLASS="{{ host_node_class }}"
# End of templated code

usage() {
    echo $* >&2
    echo "usage: prepare_node <node-type> <node-instance>" >&2
    exit 1
}

fail() {
    echo $* >&2
    exit 1
}

find_host_ip_by_mac() {
    # Lookup the IP address on the interface that has the provided MAC
    # address.
    mac="${1}"; shift || fail "find_host_by_mac requires a MAC adddress"

    ip -j a | \
        jq -r ".[] | (select(.address == \"$mac\")) \
                | .addr_info \
                | .[] | (select(.family == \"inet\")) \
                | .local"
}

find_host_ip_by_instance() {
    # Look up the IP address based on the list of host MACs and the provided
    # host instance number
    instance="${1}"; shift || fail "find_host_by_instance requires instance number"
    
    find_host_ip_by_mac "${HOST_MACS[${instance}]}"
}

# Get the command line arguments, expecting a node type name and an
# instance number in that order.
NODE_TYPE="${1}"; shift || usage "no node type specified"
NODE_INSTANCE="${1}"; shift || usage "no node instance number specified"

# If this node is not one of the host nodes, there is nothing to do
if [ "${NODE_TYPE}" != "${HOST_NODE_CLASS}" ]; then
    # Not the OpenCHAMI host node, nothing to do, just succeed
    exit 0
fi

# This is a host node, so set up OpenCHAMI and get it running and
# initialized
./OpenCHAMI-Prepare.sh "$(find_host_ip_by_instance "${NODE_INSTANCE}")" 
while ! ./OpenCHAMI-Deploy.sh; do
    ./OpenCHAMI-Remove.sh
done
# Just to show it worked, dump out the discovered nodes
./OpenCHAMI-Show.sh
