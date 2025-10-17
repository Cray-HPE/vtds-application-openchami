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

# Report a failure message on stderr
function _bi_fail() {
    local func=${FUNCNAME[1]:-"unknown-function"} # Calling function
    local message="${*:-"failing for no specified reason"}"
    echo "${func}: ${message}" >&2
    return 1
}

function build-image() (
    set -e
    local config="${1}"; shift || _bi_fail "image config file not specified"
    # Build with the specified builder. Default to using the RH9 builder
    local builder="${1:-"ghcr.io/openchami/image-build-el9:v0.1.1"}"
    [[ -f "${config}" ]] || fail "${config} not found"
    podman run \
           --network=host \
           --rm \
           --device /dev/fuse \
           -e S3_ACCESS=admin \
           -e S3_SECRET=admin123 \
           -v "$(realpath "${config}")":/home/builder/config.yaml:Z \
           ${EXTRA_PODMAN_ARGS} \
           "${builder}" \
           image-build \
           --config config.yaml \
           --log-level DEBUG || fail "cannot build image defined in ${config}"
)

function build-image-rh9() {
    local config="${1}"; shift || _bi_fail "image config file not specified"
    build-image "${config}"
}

function build-image-rh8() {
    local config="${1}"; shift || _bi_fail "image config file not specified"
    local builder="ghcr.io/openchami/image-build:v0.1.0"
    build-image "${config}" "${builder}"
}

function turn_on_node() {
    local bmc_ip="${1}"; shift || _bi_fail "no BMC IP Address provided"
    local node_xname="${1}"; shift || _bi_fail "no node XNAMEprovided"
    local bmc_user="${1}"; shift || bmc_user="root"
    local bmc_password="${1}"; shift || bmc_password="root_password"
    local bmc_url="https://${bmc_ip}/redfish/v1/Systems"
    local node_action="${node_xname}/Actions/ComputerSystem.Reset"

    curl -k -u "${bmc_user}:${bmc_password}" \
         -H "Content-Type: application/json" \
         -X POST -d '{"ResetType": "On" }' \
         "${bmc_url}/${node_action}"
}

function turn_off_node() {
    local bmc_ip="${1}"; shift || _bi_fail "no BMC IP Address provided"
    local node_xname="${1}"; shift || _bi_fail "no node XNAMEprovided"
    local bmc_user="${1}"; shift || bmc_user="root"
    local bmc_password="${1}"; shift || bmc_password="root_password"
    local bmc_url="https://${bmc_ip}/redfish/v1/Systems"
    local node_action="${node_xname}/Actions/ComputerSystem.Reset"

    curl -k -u "${bmc_user}:${bmc_password}" \
         -H "Content-Type: application/json" \
         -X POST -d '{"ResetType": "ForceOff" }' \
         "${bmc_url}/${node_action}"
}

function restart_node() {
    local bmc_ip="${1}"; shift || _bi_fail "no BMC IP Address provided"
    local node_xname="${1}"; shift || _bi_fail "no node XNAMEprovided"
    local bmc_user="${1}"; shift || bmc_user="root"
    local bmc_password="${1}"; shift || bmc_password="root_password"
    local bmc_url="https://${bmc_ip}/redfish/v1/Systems"
    local node_action="${node_xname}/Actions/ComputerSystem.Reset"

    curl -k -u "${bmc_user}:${bmc_password}" \
         -H "Content-Type: application/json" \
         -X POST -d '{"ResetType": "ForceRestart" }' \
         "${bmc_url}/${node_action}"
}
