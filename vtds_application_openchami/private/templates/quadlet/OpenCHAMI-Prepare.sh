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

# Set up the system level pieces needed to start deploying
# OpenCHAMI. This script is intended to be run by a user with
# passwordless 'sudo' permissions. The base node preparation script
# sets up the user 'rocky' with that before chaining here.
set -e -o pipefail

function fail() {
    msg="$*"
    echo "ERROR: ${msg}" >&2
    exit 1
}

# Some useful variables that can be templated
HEADNODE_FQDN="demo.openchami.cluster"
LIBVIRT_HEADNODE_IP="172.16.0.254"
LIBVIRT_NET_LENGTH="24"
LIBVIRT_NET_MASK="255.255.255.0"  # Computed from length when tempated
NMN_HEADNODE_IP="10.1.1.11"  # XXX - This needs to be discovered or templated

# Create the directories that are needed for deployment and must be
# made by 'root'
for dir in /data/oci /data/s3 /opt/workdir; do
    echo "Making directory: ${dir}"
    sudo mkdir -p "${dir}"
    sudo chown -R rocky: "${dir}"
done

# Make the directories that are needed for deployment and can be made by rocky
for dir in /opt/workdir/nodes /opt/workdir/images /opt/workdir/boot /opt/workdir/cloud-init; do
    echo "Making directory: ${dir}"
    mkdir -p '${dir}'
done

# Turn on IPv4 forwarding on the management node to allow other nodes
# to reach OpenCHAMI services
sudo sysctl -w net.ipv4.ip_forward=1

# Create a virtual bridged network within libvirt to act as the node
# local network used by OpenCHAMI services.
#
# XXX - Creation of this should be templated and configurable, as
#       should the network IP and the head node IP.
echo "Setting up libvirt bridge network for OpenCHAMI"
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
  <forward mode='route'/>
   <ip address="${LIBVIRT_HEADNODE_IP}" netmask="${LIBVIRT_NET_MASK}">
   </ip>
</network>
EOF
sudo virsh net-destroy openchami-net || true
sudo virsh net-undefine openchami-net || true
sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net

# Set up an /etc/hosts entry for the OpenCHAMI head node so we can use
# it for certs and for reaching the services.
#
# XXX - This should be templated so it is configurable, both IP and FQDM
echo "Adding head node (${LIBVIRT_HEADNODE_IP}) to /etc/hosts"
echo "${LIBVIRT_HEADNODE_IP} ${HEADNODE_FQDN}" | sudo tee -a /etc/hosts > /dev/null

# Set up the quadlet container definition to launch minio as an S3 server
echo "Setting up minio container for quadlet service"
sudo cp /root/minio.container /etc/containers/systemd/minio.container

# Set up the quadlet container definition to launch a container registry
echo "Setting up registry container for quadlet service"
sudo cp /root/registry.container /etc/containers/systemd/registry.container

# Reload systemd to pick up the minio and registry containers and then
# start those services
echo "Restarting systemd and starting minio and registry services"
sudo systemctl daemon-reload
sudo systemctl stop minio.service
sudo systemctl start minio.service
sudo systemctl stop registry.service
sudo systemctl start registry.service

# Install openchami from RPMs
#
# XXX - the VERSION here should be templated and configurable
echo "Finding OpenCHAMI RPM"
OWNER="openchami"
REPO="release"
OPENCHAMI_VERSION="latest"

# Identify the version's release RPM
API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/${OPENCHAMI_VERSION}"
release_json=$(curl -s "$API_URL")
rpm_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n 1)
rpm_name=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .name' | head -n 1)

# Download the RPM
echo "Downloading OpenCHAMI RPM"
curl -L -o "$rpm_name" "$rpm_url"

# Install the RPM
echo "Installing OpenCHAMI RPM"
if systemctl status openchami.target; then
    sudo systemctl stop openchami.target
fi
sudo rpm -Uvh --reinstall "$rpm_name"

# Set up the CoreDHCP configuration to support network booting Compute Nodes
echo "Setting up CoreDHCP Configuration"
sudo cp /root/coredhcp.yaml /etc/openchami/configs/coredhcp.yaml

# Set up Cluster SSL Certs for the
#
# XXX - this needs to be templated to use the configured FQDN of the head node
echo "Setting up cluster SSL certs for OpenCHAMI"
sudo openchami-certificate-update update demo.openchami.cluster

# Start OpenCHAMI
echo "Starting OpenCHAMI"
sudo systemctl start openchami.target

# Install the OpenCHAMI CLI client (ochami)
echo "retrieving OpenCHAMI CLI (ochami) RPM"
OCHAMI_CLI_VERSION="latest"
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/${OCHAMI_CLI_VERSION} | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
echo "Installing OpenCHAMI CLI (ochami) RPM"
sudo dnf install -y ./ochami.rpm

# Configure the OpenCHAMI CLI client
#
# XXX- This needs to be templated to use the configured FQDN of the head node
echo "Configuring OpenCHAMI CLI (ochami) Client"
sudo rm -f /etc/ochami/config.yaml
echo y | sudo ochami config cluster set --system --default demo cluster.uri "https://demo.openchami.cluster:8443" || fail "failed to configure OpenCHAMI CLI"
