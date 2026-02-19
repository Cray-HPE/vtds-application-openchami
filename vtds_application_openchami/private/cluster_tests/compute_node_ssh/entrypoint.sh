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
source ~/openchami-files/prep_setup.sh

# Get the directory the script resides in so we can find other test
# files.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_nids() {
    # Format a list of nid-xxx names that comprise the managed nodes
    # on the cluster using the templated list of NIDs known by vTDS
{%- for node in nodes %}
    printf "nid-%03d " "{{ node.nid }}"
{%- endfor %}
    echo
}

ssh_to_compute_nodes() {
    retval=0
    for nid in $(get_nids); do
        echo -n "Attempting to SSH to ${nid}"
        for retry in {0..30}; do
            echo -n "."
            if ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=10 \
                   root@"${nid}" "true"; then
                break;
            fi
            if [[ "${retry}" == 30 ]]; then
                retval=1
                echo
                echo "failed to SSH to '${nid}'"
                break
            fi
            sleep 10
        done
    done
    return "${retval}"
}

main() {
    # Arguments are 'name' is the test name from the config,
    # 'description' is the test description from the config, 'timeout'
    # is the timeout in seconds from the config.
    ssh_to_compute_nodes
}

main "${@}"
