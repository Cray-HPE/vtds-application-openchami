#! /usr/bin/bash
set -e -o pipefail
cd /root/deployment-recipes/quickstart
source bash_functions.sh
get_ca_cert > cacert.pem
ACCESS_TOKEN=$(gen_access_token)
curl \
    --cacert cacert.pem \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://foobar.openchami.cluster:8443/hsm/v2/State/Components | jq
