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

fail() {
    echo $* >&2
    exit 1
}

cd /root/deployment-recipes/quickstart || \
    fail "can't chdir to '/root/deployment-recipes/quickstart'"
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
       -f magellan_discovery.yml \
       down --volumes || \
    fail "removing OpenCHAMI deployment failed"
