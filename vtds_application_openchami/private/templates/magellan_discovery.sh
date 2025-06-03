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
export emulator_username={{ emulator_username }}
export emulator_password={{ emulator_password }}
export PATH=$PATH:/
export MASTER_KEY=$(magellan secrets generatekey)
{% for network in discovery_networks %}
magellan scan --subnet {{ network.cidr }}
{% endfor %}
magellan list
cd /tmp/nobody/magellan
magellan list | awk '{print $1}' | xargs -I{} magellan secrets store {} $emulator_username:$emulator_password
magellan secrets list
magellan secrets list | awk '{print $1}' | sed -e 's/:$//' | xargs -I{} magellan secrets retrieve {}
export ACCESS_TOKEN=$(curl -s -X GET http://opaal:3333/token | sed 's/.*"access_token":"\([^"]*\).*/\1/')
magellan collect --host http://smd:27779 --access-token "$ACCESS_TOKEN"
