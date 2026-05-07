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

# Set up the system level pieces needed to start deploying
# OpenCHAMI. This script is intended to be run by a user with
# passwordless 'sudo' permissions. The base node preparation script
# sets up the user 'rocky' with that before chaining here.

# Set up error handling, the environment and some functions for
# running the "prepare" scripts...
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

cd "${VTDSDIR}"

# Make a python virtual environment for the deployment tool to live in
VENV="${HOME}/venv"
python3 -m venv "${VENV}"

# Clone the deployment tool repo, switch to the correct version and
# install it in the virtual environment
cd "${VTDSDIR}"
rm -rf deploy-openchami
"${VENV}/bin/pip" uninstall -y deploy-openchami || true
git clone "{{ deployment.deployment_tool.url }}" deploy-openchami
cd deploy-openchami
git checkout "{{ deployment.deployment_tool.version }}"
"${VENV}/bin/pip" install .

# Retrieve any deployment overlays specified in the configuration for
# use with the deployment tool
cd "${VTDSDIR}"
DEPLOY_OVERLAYS=""
{%- for overlay_url in deployment.deployment_tool.overlays %}
OVERLAY_FILE="$(mktemp --suffix .yaml)"
curl -s -o "{{ overlay_url }}" "${OVERLAY_FILE}"
DEPLOY_OVERLAYS="${DEPLOY_OVERLAYS} ${OVERLAY_FILE}"
{%- endfor %}

# Now prepare the deployment and run it
cd "${VTDSDIR}"
echo "Preparing OpenCHAMI head node for deployment"
sudo "${VENV}/bin/deploy_openchami" -p ${DEPLOY_OVERLAYS} cluster_overlay.yaml
echo "Deploying OpenCHAMI on head node"
sudo "${VENV}/bin/deploy_openchami" ${DEPLOY_OVERLAYS} cluster_overlay.yaml
