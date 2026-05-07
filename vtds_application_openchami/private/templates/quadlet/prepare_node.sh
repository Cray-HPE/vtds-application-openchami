#! /usr/bin/bash
#
# MIT License
#
# (C) Copyright 2025-2026 Hewlett Packard Enterprise Development LP
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

MANAGEMENT_NODE_CLASS="{{ host_node_class }}"

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

# This is a management node, so set up for OpenCHAMI deployment
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
# In case OpenCHAMI is already installed, we want to remove it so we
# don't conflict with it
dnf -y remove openchami || true
if ! getent group rocky; then
    groupadd rocky
fi
if ! getent passwd rocky; then
    useradd -g rocky rocky
fi
# Remove rocky from /etc/sudoers and then put it back with NOPASSWD access
sed -i -e '/[[:space:]]*rocky/d' /etc/sudoers
echo 'rocky ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Copy the cluster testing tree (if any) to the 'rocky' user
if [ -d ~/cluster_tests ]; then
    cp -r ~/cluster_tests ~rocky/cluster_tests
    chown -R rocky: ~rocky/cluster_tests
fi

# Create directories that support 'rocky' running the deployment tool
# and copy files into them.
mkdir -p "${VTDSDIR}"
chown -R rocky "${VTDSDIR}"
chmod 755 "${VTDSDIR}"
mkdir -p "${BINDIR}"
chown -R rocky "${BINDIR}"
chmod 755 "${BINDIR}"
cp /root/prep_setup.sh "${BINDIR}/prep_setup.sh"
chown rocky "${BINDIR}/prep_setup.sh"
chmod 644 "${BINDIR}/prep_setup.sh"
cp /root/OpenCHAMI-Deploy.sh "${BINDIR}/OpenCHAMI-Deploy.sh"
chown rocky "${BINDIR}/OpenCHAMI-Deploy.sh"
chmod 755 "${BINDIR}/OpenCHAMI-Deploy.sh"
cp /root/cluster_overlay.yaml "${VTDSDIR}/cluster_overlay.yaml"
chown rocky "${VTDSDIR}/cluster_overlay.yaml"

# Run OpenCHAMI preparation script as 'rocky'
su - rocky -c "${BINDIR}/OpenCHAMI-Deploy.sh"
