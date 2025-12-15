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

# Set up error handling, the environment and some functions for
# running the "prepare" scripts...
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/openchami-files/prep_setup.sh"

# Get some image building functions into our environment
source "${SCRIPT_DIR}/openchami-files/build-image.sh"

# List the image builder configuration files to use for building the
# base OS image, the compute node base image and the compute node
# debug image.
#
# XXX - Once these are templated, we might want to rename the files to
#       reflect their more generalized natures. For now this is
#       accurate.
IMAGE_BUILDERS=(
    "rocky-base-9.yaml"
    "compute-base-rocky9.yaml"
    "compute-debug-rocky9.yaml"
)

ROCKY_DIRS=(
    "/data/oci"
    "/data/s3"
    "/opt/workdir"
)

WORK_DIRS=(
    "/opt/workdir/nodes"
    "/opt/workdir/images"
    "/opt/workdir/boot"
    "/opt/workdir/cloud-init"
)

S3_PUBLIC_BUCKETS=(
    "efi"
    "boot-images"
)

# Create the directories that are needed for deployment and must be
# made by 'root'
for dir in "${ROCKY_DIRS[@]}"; do
    echo "Making directory: ${dir}"
    sudo mkdir -p "${dir}"
    sudo chown -R rocky: "${dir}"
done

# Make the directories that are needed for deployment and can be made
# by rocky
for dir in "${WORK_DIRS[@]}"; do
    echo "Making directory: ${dir}"
    mkdir -p "${dir}"
done

# Turn on IPv4 forwarding on the management node to allow other nodes
# to reach OpenCHAMI services
sudo sysctl -w net.ipv4.ip_forward=1

# Set up an /etc/hosts entry for the OpenCHAMI management head node so
# we can use it for certs and for reaching the services.
echo "Adding head node (${MANAGEMENT_HEADNODE_IP}) to /etc/hosts"
echo "${MANAGEMENT_HEADNODE_IP} ${MANAGEMENT_HEADNODE_FQDN}" | \
    sudo tee -a /etc/hosts > /dev/null

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
cd /opt/workdir
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
    # Also remove any SMD or BSS data after
    # giving the pods a chance to stop
    sleep 5
    sudo podman volume rm postgres-data
fi
sudo rpm -Uvh --reinstall "$rpm_name"

# Patch a bug in the coresmd-coredns container file...
patch_coredns

# Set up the configuration for Core-SMD CoreDNS
echo "Setting up Core-SMD CoreDNS"
sudo cp "${SCRIPT_DIR}/openchami-files/Corefile" /etc/openchami/configs/Corefile

# Set up the CoreDHCP configuration to support network booting Compute Nodes
echo "Setting up CoreDHCP Configuration"
sudo cp /root/coredhcp.yaml /etc/openchami/configs/coredhcp.yaml

# Set up Cluster SSL Certs for the
echo "Setting up cluster SSL certs for OpenCHAMI"
sudo openchami-certificate-update update "${MANAGEMENT_HEADNODE_FQDN}"

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
echo "Configuring OpenCHAMI CLI (ochami) Client"
sudo rm -f /etc/ochami/config.yaml
echo y | sudo ochami config cluster set --system --default demo \
              cluster.uri "https://${MANAGEMENT_HEADNODE_FQDN}:8443" \
    || fail "failed to configure OpenCHAMI CLI"

# Copy the application data files into their respective places so we are
# ready to build and boot compute nodes.
#
# Copy the static node discovery inventory into place
cp "${SCRIPT_DIR}/openchami-files/nodes.yaml" /opt/workdir/nodes/nodes.yaml

# Set up the 'rocky' user's S3 configuration
cp "${SCRIPT_DIR}/openchami-files/s3cfg" ~/.s3cfg

# Copy the S3 publicly readable EFI and Boot file settings into place
cp "${SCRIPT_DIR}"/openchami-files/s3-public-read-* /opt/workdir/

# Move the image builder configurations into place
for builder in "${IMAGE_BUILDERS[@]}"; do 
    cp "${SCRIPT_DIR}/openchami-files/${builder}" /opt/workdir/images/"${builder}"
done

# Add the image builder functions to the bash default environment for
# future use
sudo cp "${SCRIPT_DIR}/openchami-files/build-image.sh" /etc/profile.d/build-image.sh

# All the vTDS constructed files have been installed in their
# respective locations, time to set things up and build some images.
#
# The first thing we need is credentials to interact with
# OpenCHAMI. Since OpenCHAMI just came up, this might not work the
# first time, so retry a few times.
for i in {1..10}; do
    get-ochami-token || DEMO_ACCESS_TOKEN=""
    if [[ "${DEMO_ACCESS_TOKEN}" != "" ]]; then
        break
    fi
    sleep 10
done
[[ "${DEMO_ACCESS_TOKEN}" != "" ]] || fail "cannot get openchami access token"

# Wait for SMD to be up and running. This can sometimes take a little
# while. If it takes more than 100 seconds, something is probably
# wrong.
smd_running=false
for i in {1..10}; do
    if ochami smd component get > /dev/null 2>&1; then
        smd_running=true
        break
    fi
    sleep 10
done
if ! ${smd_running}; then
    fail "timeout waiting for SMD to start, openChami is not fully available"
fi

# Run the static node discovery
ochami discover static $(discovery_version) -f yaml -d @/opt/workdir/nodes/nodes.yaml

# Install and configure 'regctl'
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 > regctl \
    && sudo mv regctl /usr/local/bin/regctl \
    && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled "${MANAGEMENT_HEADNODE_FQDN}:5000"

# Install and configure S3 client
for bucket in "${S3_PUBLIC_BUCKETS[@]}"; do
    s3cmd ls | grep s3://"${bucket}" && s3cmd rb -r s3://"${bucket}"
    s3cmd mb s3://"${bucket}"
    s3cmd setacl s3://"${bucket}" --acl-public
    s3cmd setpolicy /opt/workdir/s3-public-read-"${bucket}".json \
          s3://"${bucket}" \
          --host="${MANAGEMENT_HEADNODE_IP}:9000" \
          --host-bucket="${MANAGEMENT_HEADNODE_IP}:9000"
done

# Build the Base Image
echo "Building the Common Base OS Image"
build-image /opt/workdir/images/rocky-base-9.yaml

# Build the Compute Node Base Image
echo "Building the Compute Node Base OS image"
build-image /opt/workdir/images/compute-base-rocky9.yaml

# Build the Compute Node Debug Image
echo "Building the Compute Node Debug OS image"
build-image /opt/workdir/images/compute-debug-rocky9.yaml

# Make sure coresmd-coredns is running by now. If it is not, we have a
# problem and we don't want to switch over to it...
systemctl is-active --quiet coresmd-coredns.service || \
    fail "coresmd-coredns is not active, ivestigate why not and try again"

# Switch to coresmd-coredns as the nameserver
echo "Switching to the cluster internal DNS nameserver"
switch_dns "${MANAGEMENT_HEADNODE_IP}" "${CLUSTER_DOMAIN}"

# Refresh ochami token after the image builds in case it expired
export DEMO_ACCESS_TOKEN="$(sudo bash -lc 'gen_access_token')"

# Create the boot configuration for the Compute node Debug image
echo "Creating the debug boot configuration"
cd /opt/workdir/boot
generate-boot-config \
    "compute/debug" \
    "${MANAGEMENT_HEADNODE_IP}" \
    $(managed_macs) | \
    tee /opt/workdir/boot/boot-compute-debug.yaml

# Create the boot configuration for the Compute node Base image
echo "Creating the base boot configuration"
cd /opt/workdir/boot
generate-boot-config \
    "compute/base" \
    "${MANAGEMENT_HEADNODE_IP}" \
    $(managed_macs) | \
    tee /opt/workdir/boot/boot-compute-base.yaml

# Install the boot configuration for the debug kernel
echo "Install boot configuration"
ochami bss boot params set -f yaml \
       -d @/opt/workdir/boot/boot-compute-debug.yaml

# Set up cloud-init for some basics...
#
# First the global cloud-init metadata
# XXX - Need some templating here...
rm -f ~/.ssh/id_rsa*
ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""
mkdir -p /opt/workdir/cloud-init
cat <<EOF | tee /opt/workdir/cloud-init/ci-defaults.yaml
---
base-url: "http://${MANAGEMENT_HEADNODE_IP}:8081/cloud-init"
cluster-name: "demo"
nid-length: 3
public-keys:
  - "$(cat ~/.ssh/id_rsa.pub)"
short-name: "nid"
EOF
ochami cloud-init defaults set -f yaml \
       -d @/opt/workdir/cloud-init/ci-defaults.yaml

# Next the cloud init metadata for the managed node groups...
for group in $(node_groups); do
    cat <<EOF | tee /opt/workdir/cloud-init/ci-group-"${group}".yaml
- name: ${group}
  description: "${group} group config"
  file:
    encoding: plain
    content: |
      ## template: jinja
      #cloud-config
      merge_how:
      - name: list
        settings: [append]
      - name: dict
        settings: [no_replace, recurse_list]
      users:
        - name: testuser
          ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
        - name: root
          ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
      disable_root: false
EOF
    ochami cloud-init group set -f yaml \
           -d @/opt/workdir/cloud-init/ci-group-"${group}".yaml
done
{%- for node in nodes %}
ochami cloud-init node set \
       -d '[{"id":"{{ node.xname }}","local-hostname":"{{ node.hostname}} "}]'
{%- endfor %}

# Now that all the images are in place, cloud-init is set up and the
# managed nodes have been configured, go through and start them all
# using RedFish curls.
{%- for node in nodes %}
power-on-node "{{ node.xname }}" "{{ node.bmc_xname }}"
{%- endfor %}
