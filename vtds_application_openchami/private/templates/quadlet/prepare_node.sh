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

OPENCHAMI_FILES=(
    "nodes.yaml"
    "s3cfg"
    "s3-public-read-boot.json"
    "s3-public-read-efi.json"
    "rocky-base-9.yaml"
    "compute-base-rocky9.yaml"
    "compute-debug-rocky9.yaml"
    "build-image.sh"
    "boot-compute-debug.yaml"
)

usage() {
    echo $* >&2
    echo "usage: prepare_node <node-type> <node-instance>" >&2
    exit 1
}

fail() {
    echo $* >&2
    exit 1
}

# Get the command line arguments, expecting a node type name and an
# instance number in that order.
NODE_TYPE="${1}"; shift || usage "no node type specified"
NODE_INSTANCE="${1}"; shift || usage "no node instance number specified"

# If this node is not one of the management nodes, there is nothing to do
if [ "${NODE_TYPE}" != "${HOST_NODE_CLASS}" ]; then
    # Not the OpenCHAMI management node, nothing to do, just succeed
    exit 0
fi

# This is a management node, so set up OpenCHAMI and get it running and
# initialized
PACKAGES="libvirt qemu-kvm virt-install virt-manager dnsmasq podman buildah git vim emacs ansible-core openssl nfs-utils"
dnf -y check-update || true
dnf -y install ${PACKAGES}
dnf -y install epel-release
dnf -y install s3cmd
systemctl enable --now libvirtd
if ! getent group rocky; then
    groupadd rocky
fi
if ! getent passwd rocky; then
    useradd -g rocky -G libvirt rocky
fi
# Remove rocky from /etc/sudoers and then put it back with NOPASSWD access
sed -i -e '/[[:space:]]*rocky/d' /etc/sudoers
echo 'rocky ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Copy prepared data files to the 'rocky' user
mkdir ~rocky/openchami-files
for file in "${OPENCHAMI_FILES[@]}"; do
    cp "${file}" ~rocky/openchami-files/"${file}"
done
chown -R rocky: ~rocky/openchami-files

# Run OpenCHAMI preparation script as 'rocky'
cp /root/OpenCHAMI-Prepare.sh ~rocky/OpenCHAMI-Prepare.sh
chown rocky ~rocky/OpenCHAMI-Prepare.sh
chmod 755 ~rocky/OpenCHAMI-Prepare.sh
su - rocky -c "~rocky/OpenCHAMI-Prepare.sh"
