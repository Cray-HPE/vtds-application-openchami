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

fail() {
    echo $* >&2
    exit 1
}

cd /root/deployment-recipes/quickstart || \
    fail "can't chdir to '/root/deployment-recipes/quickstart'"
source bash_functions.sh || \
    fail "unable to load quickstart shell functions"
get_ca_cert > cacert.pem || \
    fail "unable to initialize SSL cert for access to hsm"
ACCESS_TOKEN="$(gen_access_token)" || \
    fail "unable to obtain access tokent for access to hsm"
curl \
    --cacert cacert.pem \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://foobar.openchami.cluster:8443/hsm/v2/State/Components | \
    jq || \
    fail "attempt to retrieve component state from hsm failed"
