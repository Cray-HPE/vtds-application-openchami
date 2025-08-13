#! /usr/sbin/sh
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
export PATH="$PATH":/
mkdir -p /tmp/nobody/magellan
cd /tmp/nobody/magellan
export MASTER_KEY="$(magellan secrets generatekey)"
echo "${MASTER_KEY}" > /tmp/nobody/magellan/master_key # Keep it around for debug
export ACCESS_TOKEN="$(curl -s -X GET http://opaal:3333/token | sed 's/.*"access_token":"\([^"]*\).*/\1/')"
cp /bmc-id-map.yaml .
         
# Keep track of the servers we have seen so we can avoid overwriting secrets
#
# NOTE: this method is does not scale well. It works okay for vTDS
#       systems which won't be likely to have more than 4 or so
#       servers. We really need a way to have magellan list only
#       servers that are on a specific network (CIDR) if we are going
#       to use it this way.
rm -f rf_servers
touch rf_servers

{%- for network in discovery_networks %}
# Scan and store creds for subnet {{ network.cidr }}
magellan scan --subnet {{ network.cidr }}
servers="$(magellan list | awk '{print $1}')"
creds="{{ network.redfish_username }}:{{ network.redfish_password }}"
for server in ${servers}; do
    if grep -F "${server}" rf_servers; then
        # Skip servers we have already seen
        continue
    fi
    # New server, store its creds
    magellan secrets store "${server}" "${creds}"
    # Remember we saw this one.
    echo "${server}" >> rf_servers
done
{% endfor %}

# Collect and deliver the node data
magellan collect -v --format yaml --output-file nodes.yaml --bmc-id-map @bmc-id-map.yaml
magellan send --format yaml -d @nodes.yaml http://smd:27779 --access-token "$ACCESS_TOKEN"
# The following is helpful for debugging. It keeps the container
# running so you can drop into it. The container uses very little
# in the way of resources, so it is not bad to keep around.
while true; do sleep 600; done
