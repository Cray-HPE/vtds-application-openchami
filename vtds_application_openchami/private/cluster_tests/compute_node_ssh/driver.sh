#
# MIT License
#
# (C) Copyright 2026 Hewlett Packard Enterprise Development LP
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
set -e -u -o pipefail

source "prep_setup.sh"

trap timeout_hadler ALRM
TEST_NAME=""        # filled in by main
TEST_TIMEOUT=""     # filled in by main
TEST_DESCRIPTION="" # filled in by main

timeout_handler() {
    fail "'${TEST_NAME}' timed out after ${TEST_TIMEOUT} seconds"
    exit 1
}

usage() {
    msg="${1}\n"; shift || msg=""
    printf "$msg" >&2
    echo "usage: driver.sh name desc timeout config" >&2
    echo "    where:" >&2
    echo "       'name' is the test name" >&2
    echo "       'desc' is the test description" >&2
    echo "       'timeout' is a timeout value in seconds for the test run" >&2
    echo "       'config' is the path to the application layer config file" >&2
    exit 1
}

get_nids() {
    local compute_count=4 # TODO - TEMPLATE THIS OR BASE IT ON CONFIG
    nids="$(
        for ((i=1; i <= "${compute_count}"; i++)); do
            printf "nid-%03d " $i;
        done
    )"
    echo "${nids}"
}

ssh_to_compute_nodes() {
    retval=0
    for nid in $(get_nids "${config}"); do
        for retry in {0..30}; do
            if ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=10 \
                   root@"${nid}" "exit 0"; then
                break;
            fi
            if [[ "${retry}" == 30 ]]; then
                fail "failed to SSH to '${nid}'"
            fi
            sleep 10
        done
    done
    return "${retval}"
}

main() {
    # Arguments are 'name' is the test name from the config,
    # 'description' is the test description from the config, 'timeout'
    # is the timeout in seconds from the config, 'config' is the path
    # to the application layer configuration file used for this
    # deployment.
    TEST_NAME="${1}"; shift || usage "missing test name"
    TEST_DESCRIPTION="${1}"; shift || usage "missing test description"
    local timeout="${1}"; shift || usage "missing test timeout value"
    local configuration="${1}"; shift || usage "missing config file path"
    
    # Set up a timeout right now so that we don't get stuck
    ( sleep "${timeout}" && kill -ALRM $$) &

    # Run the test...
    ssh_to_compute_nodes()
}

main "$@"
