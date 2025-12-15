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

# Pick up the common setup for the prepare scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

OPENCHAMI_FILES=(
    "nodes.yaml"
    "s3cfg"
    "rocky-base-9.yaml"
    "compute-base-rocky9.yaml"
    "compute-debug-rocky9.yaml"
    "build-image.sh"
    "boot-compute-debug.yaml"
    "Corefile"
    "containers.conf"
    "s3-public-read-boot-images.json"
    "s3-public-read-efi.json"
    "prep_setup.sh"
)
# These files need to have their copyright comments stripped from them
# because the comments break parsing.
STRIP_COMMENT_FILES=(
    "s3-public-read-boot-images.json"
    "s3-public-read-efi.json"
    "bmc_info.json"    # Do not put this in ~rocky/openchami-files
)


usage() {
    echo $* >&2
    echo "usage: prepare_node <node-type> <node-instance>" >&2
    exit 1
}

# Get the command line arguments, expecting a node type name and an
# instance number in that order.
NODE_TYPE="${1}"; shift || usage "no node type specified"
NODE_INSTANCE="${1}"; shift || usage "no node instance number specified"

# If this node is not one of the management nodes, there is nothing to do
if [ "${NODE_TYPE}" != "${MANAGEMENT_NODE_CLASS}" ]; then
    # Not the OpenCHAMI management node, nothing to do, just succeed
    exit 0
fi

# Move the NAMESERVER for the management node over to the external
# nameserver hosted by the host blade and add the cluster domain to
# the domain search path. Since the nameserver here will be on the
# management network but not local, specify the local IP on the
# management network as the network parameter to switch_dns.
switch_dns "${MANAGEMENT_EXT_NAMESERVER}" "${CLUSTER_DOMAIN}" "${MANAGEMENT_HEADNODE_IP}"

# This is a management node, so set up OpenCHAMI and get it running and
# initialized
PACKAGES="\
        dnsmasq\
        podman\
        buildah\
        git\
        vim\
        emacs\
        ansible-core\
        openssl\
        nfs-utils\
"
dnf -y check-update || true
dnf -y install ${PACKAGES}
dnf -y install epel-release
dnf -y install s3cmd
if ! getent group rocky; then
    groupadd rocky
fi
if ! getent passwd rocky; then
    useradd -g rocky rocky
fi
# Remove rocky from /etc/sudoers and then put it back with NOPASSWD access
sed -i -e '/[[:space:]]*rocky/d' /etc/sudoers
echo 'rocky ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Set the interface name in coredhcp.yaml
sed -i \
    -e "s/::MGMT_NET_HEAD_IFNAME::/${MGMT_NET_HEAD_IFNAME}/g" \
    coredhcp.yaml

# Strip comments out of prepared data files as needed.
for file in "${STRIP_COMMENT_FILES[@]}"; do
    sed -i \
        -e "/^[[:blank:]]*#/d" \
        -e "s/[[:blank:]]*#.*$//" \
        "${file}"
done

# Copy the BMC information into /etc/vtds and make sure it is not
# publicly readable since it contains RedFish passwords for BMCs.
chmod 600 bmc_info.json
chown root:root bmc_info.json
mkdir -p /etc/vtds
cp bmc_info.json /etc/vtds/bmc_info.json
chmod 600 /etc/vtds/bmc_info.json
chown root:root /etc/vtds/bmc_info.json

# Copy prepared data files to the 'rocky' user
mkdir -p ~rocky/openchami-files
for file in "${OPENCHAMI_FILES[@]}"; do
    cp "${file}" ~rocky/openchami-files/"${file}"
done
chown -R rocky: ~rocky/openchami-files

# Run OpenCHAMI preparation script as 'rocky'
cp /root/OpenCHAMI-Prepare.sh ~rocky/OpenCHAMI-Prepare.sh
chown rocky ~rocky/OpenCHAMI-Prepare.sh
chmod 755 ~rocky/OpenCHAMI-Prepare.sh
su - rocky -c "~rocky/OpenCHAMI-Prepare.sh"
