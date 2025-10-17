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

# Get some image building functions into our environment
source ~rocky/openchami-files/build-image.sh

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

function fail() {
    msg="$*"
    echo "ERROR: ${msg}" >&2
    exit 1
}

function discovery_version() {
    # The version of SMD changed how ochami needs to feed it manually
    # discovered node data at 2.19. We need an extra option to address
    # that if the version is 2.18 or lower.
    local major=""
    local minor=""
    local patch=""
    IFS='.' read major minor patch < \
       <( \
          sudo podman ps | \
              grep '/smd:v' | \
              awk '{sub(/^.*:v/, "", $2); print $2 }'\
       )
    if [ "${major}" -le "2" -a "${minor}" -lt "19" ]; then
       echo "--discovery-version=1"
    fi
}

# Some useful variables that can be templated
MANAGEMENT_HEADNODE_FQDN="{{ hosting_config.management.net_head_fqdn }}"
MANAGEMENT_HEADNODE_IP="{{ hosting_config.management.net_head_ip }}"
MANAGEMENT_NET_LENGTH="{{ hosting_config.management.prefix_len }}"
MANAGEMENT_NET_MASK="{{ hosting_config.management.netmask }}"
{%- if hosting_config.cohost.enable %}
LIBVIRT_NET_IP="{{ hosting_config.cohost.net_head_ip }}"
LIBVIRT_NET_LENGTH="{{ hosting_config.cohost.prefix_len }}"
LIBVIRT_NET_MASK="{{ hosting_config.cohost.netmask }}"
{%- endif %}

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

{%- if hosting_config.cohost.enable %}
# Create a virtual bridged network within libvirt to act as the node
# local network used by OpenCHAMI services.
echo "Setting up libvirt bridge network for OpenCHAMI"
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
  <forward mode='route'/>
  <ip address="${LIBVIRT_NET_IP}" netmask="${LIBVIRT_NET_MASK}" />
</network>
EOF
sudo virsh net-destroy openchami-net || true
sudo virsh net-undefine openchami-net || true
sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net

{%- endif %}
# Set up an /etc/hosts entry for the OpenCHAMI management head node so
# we can use it for certs and for reaching the services.
echo "Adding head node (${MANAGEMENT_HEADNODE_IP}) to /etc/hosts"
echo "${MANAGEMENT_HEADNODE_IP} ${MANAGEMENT_HEADNODE_FQDN}" | \
    sudo tee -a /etc/hosts > /dev/null

# Set up the configuration and quadlet container to launch CoreDNS
echo "Setting up CoreDNS"
sudo mkdir -p /etc/coredns
sudo cp ~rocky/openchami-files/Corefile /etc/coredns/Corefile
sudo cp ~rocky/openchami-files/db.openchami.cluster /etc/coredns/db.openchami.cluster
sudo cp ~rocky/openchami-files/coredns.container /etc/containers/systemd/coredns.container

# Set up the quadlet container definition to launch minio as an S3 server
echo "Setting up minio container for quadlet service"
sudo cp /root/minio.container /etc/containers/systemd/minio.container

# Set up the quadlet container definition to launch a container registry
echo "Setting up registry container for quadlet service"
sudo cp /root/registry.container /etc/containers/systemd/registry.container

# Reload systemd to pick up the minio and registry containers and then
# start those services
echo "Restarting systemd and starting CoreDNS, minio and registry services"
sudo systemctl daemon-reload
sudo systemctl stop coredns.service
sudo systemctl start coredns.service
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
fi
sudo rpm -Uvh --reinstall "$rpm_name"

# Set up the CoreDHCP configuration to support network booting Compute Nodes
echo "Setting up CoreDHCP Configuration"
sudo cp /root/coredhcp.yaml /etc/openchami/configs/coredhcp.yaml

# Set up Cluster SSL Certs for the
#
# XXX - this needs to be templated to use the configured FQDN of the head node
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
#
# XXX- This needs to be templated to use the configured FQDN of the head node
echo "Configuring OpenCHAMI CLI (ochami) Client"
sudo rm -f /etc/ochami/config.yaml
echo y | sudo ochami config cluster set --system --default demo \
              cluster.uri "https://${MANAGEMENT_HEADNODE_FQDN}:8443" \
    || fail "failed to configure OpenCHAMI CLI"

# Copy the application data files into their respective places so we are
# ready to build and boot compute nodes.
#
# Copy the static node discovery inventory into place
cp ~rocky/openchami-files/nodes.yaml /opt/workdir/nodes/nodes.yaml

# Set up the 'rocky' user's S3 configuration
cp ~rocky/openchami-files/s3cfg ~rocky/.s3cfg

# Copy the S3 publicly readable EFI and Boot file settings into place
cp ~rocky/openchami-files/s3-public-read-* /opt/workdir/

# Move the image builder configurations into place
for builder in "${IMAGE_BUILDERS[@]}"; do 
    cp ~rocky/openchami-files/"${builder}" /opt/workdir/images/"${builder}"
done

# Add the image builder functions to the bash default environment for
# future use
sudo cp ~rocky/openchami-files/build-image.sh /etc/profile.d/build-image.sh

# All the vTDS constructed files have been installed in their
# respective locations, time to set things up and build some images.
#
# The first thing we need is credentials to interact with OpenCHAMI
export DEMO_ACCESS_TOKEN="$(sudo bash -lc 'gen_access_token')"

# Run the static node discovery (first delete any previously existing content)
if [[ "$(ochami smd component get | jq ".Components | length")" -gt 0 ]]; then
    echo y | ochami smd component delete --all
fi
ochami discover static $(discovery_version) -f yaml -d @/opt/workdir/nodes/nodes.yaml || true # FOR NOW UNTIL WE FIGURE OUT WHY SMD DOESN'T LIKE nodes.yaml

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

# Create the boot configuration
echo "Creating the boot configuration"
cd /opt/workdir/boot
URIS="$(s3cmd ls -Hr s3://boot-images | grep compute/debug | awk '{print $4}' | sed "s-s3://-http://${MANAGEMENT_HEADNODE_IP}:9000/-" | xargs)"
URI_IMG="$(echo "$URIS" | cut -d' ' -f1)"
URI_INITRAMFS="$(echo "$URIS" | cut -d' ' -f2)"
URI_KERNEL="$(echo "${URIS}" | cut -d' ' -f3)"
cat <<EOF | tee /opt/workdir/boot/boot-compute-debug.yaml
---
kernel: '${URI_KERNEL}'
initrd: '${URI_INITRAMFS}'
params: 'nomodeset ro root=live:${URI_IMG} ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://${MANAGEMENT_HEADNODE_IP}:8081/cloud-init'
macs:
{%- for mac in managed_macs %}
  - {{ mac }}
{%- endfor %}
EOF

# Refresh ochami token after the image builds in case it expired
export DEMO_ACCESS_TOKEN="$(sudo bash -lc 'gen_access_token')"

# Install the boot configuration
echo "Install boot configuration"
ochami bss boot params set -f yaml -d @/opt/workdir/boot/boot-compute-debug.yaml

# Now that all the images are in place and the managed nodes have been
# configured, go through and start them all using RedFish curls.
#
# XXX - we need to add BMC user and BMC password to these actions, get
#       from config and add to template. Then pick up here as the
#       third and fourth args to 'turn_on_node'
{%- for node in nodes %}
turn_on_node "{{ node.bmc_ip }}" "{{ node.xname }}"
{%- endfor %}
