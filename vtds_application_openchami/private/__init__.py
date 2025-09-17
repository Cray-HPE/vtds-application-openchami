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
"""Module initialization

"""

from os import sep as separator
from os.path import (
    join as path_join,
    dirname
)
CONFIG_DIR = path_join(dirname(__file__), "config")
TEMPLATE_DIR_PATH = path_join(
    dirname(__file__),
    'templates',
)


def template(filename):
    """Translate a file name into a full path name to a file in the
    scripts directory.

    """
    return path_join(TEMPLATE_DIR_PATH, filename)


def home(filename):
    """Translate a filename into a full path on a remote host that is
    in the 'root' home directory.

    """
    return path_join(separator, "root", filename)


# Templated files to be deployed to the managment node: (source, dest,
# mode, tag, run)
#
# Management node files for the Quickstart recipe deployment mode
QUICKSTART_MANAGEMENT_NODE_FILES = [
    (
        template('quickstart/magellan_discovery_dockerfile'),
        home('magellan_discovery_dockerfile'),
        '644',
        'magellan-discovery-dockerfile',
        False
    ),
    (
        template('quickstart/magellan_discovery.sh'),
        home('magellan_discovery.sh'),
        '755',
        'magellan_discovery_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Stage1-Deploy.sh'),
        home('OpenCHAMI-Stage1-Deploy.sh'),
        '755',
        'OpenCHAMI_Stage1_Deploy_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Stage2-Deploy.sh'),
        home('OpenCHAMI-Stage2-Deploy.sh'),
        '755',
        'OpenCHAMI_Stage2_Deploy_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Prepare.sh'),
        home('OpenCHAMI-Prepare.sh'),
        '755',
        'OpenCHAMI_Prepare_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Remove.sh'),
        home('OpenCHAMI-Remove.sh'),
        '755',
        'OpenCHAMI_Remove_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Logs.sh'),
        home('OpenCHAMI-Logs.sh'),
        '755',
        'OpenCHAMI_Logs_script',
        False,
    ),
    (
        template('quickstart/OpenCHAMI-Show.sh'),
        home('OpenCHAMI-Show.sh'),
        '755',
        'OpenCHAMI_Show_script',
        False,
    ),
    (
        template('quickstart/prepare_node.sh'),
        home('prepare_node.sh'),
        '755',
        'node_prepare_script',
        True,
    ),
]
# Management node files for the bare system deployment mode
BARE_MANAGEMENT_NODE_FILES = [
    (
        template('bare/prepare_node.sh'),
        home('prepare_node.sh'),
        '755',
        'node_prepare_script',
        True,
    ),
]
# Management node files for the Quadlet deployment mode
QUADLET_MANAGEMENT_NODE_FILES = [
    (
        template('quadlet/minio.container'),
        home('minio.container'),
        '644',
        'minio_quadlet_container_config',
        False,
    ),
    (
        template('quadlet/registry.container'),
        home('registry.container'),
        '644',
        'registry_quadlet_container_config',
        False,
    ),
    (
        template('quadlet/coredhcp.yaml'),
        home('coredhcp.yaml'),
        '644',
        'coredhcp_config',
        False,
    ),
    (
        template('quadlet/nodes.yaml'),
        home('nodes.yaml'),
        '644',
        'manual_node_discovery_data',
        False,
    ),
    (
        template('quadlet/s3cfg'),
        home('s3cfg'),
        '644',
        'rocky_user_s3_configuration_file',
        False,
    ),
    (
        template('quadlet/s3-public-read-boot-images.json'),
        home('s3-public-read-boot-images.json'),
        '644',
        's3_boot_file_location_information',
        False,
    ),
    (
        template('quadlet/s3-public-read-efi.json'),
        home('s3-public-read-efi.json'),
        '644',
        's3_efi_location_information',
        False,
    ),
    (
        template('quadlet/rocky-base-9.yaml'),
        home('rocky-base-9.yaml'),
        '644',
        'rocky_base_compute_node_builder_specification',
        False,
    ),
    (
        template('quadlet/compute-base-rocky9.yaml'),
        home('compute-base-rocky9.yaml'),
        '644',
        'compute_node_image_builder_specification',
        False,
    ),
    (
        template('quadlet/compute-debug-rocky9.yaml'),
        home('compute-debug-rocky9.yaml'),
        '644',
        'compute_node_debug_image_builder_specification',
        False,
    ),
    (
        template('quadlet/build-image.sh'),
        home('build-image.sh'),
        '644',
        'image_builder_shell_functions_library',
        False,
    ),
    (
        template('quadlet/boot-compute-debug.yaml'),
        home('boot-compute-debug.yaml'),
        '644',
        'debug_kernel_boot_params',
        False,
    ),
    (
        template('quadlet/OpenCHAMI-Prepare.sh'),
        home('OpenCHAMI-Prepare.sh'),
        '755',
        'open_chami_prepare_script',
        False,
    ),
    (
        template('quadlet/prepare_node.sh'),
        home('prepare_node.sh'),
        '755',
        'node_prepare_script',
        True,
    ),
]

# Templated files to be deployed to and run on the Virtual Blades
BLADE_FILES = [
    (
        template('blade/nginx-default-site-config'),
        home('nginx-default-site-config'),
        '644',
        'nginx-default-site-config',
        False
    ),
    (
        template('blade/sushy-emulator.conf'),
        home('sushy-emulator.conf'),
        '644',
        'sushy-emulator-configuration',
        False
    ),
    (
        template('blade/sushy-emulator.service'),
        home('sushy-emulator.service'),
        '644',
        'sushy-emulator-unit-file',
        False
    ),
    (
        template('blade/prepare_blade.sh'),
        home('prepare_blade.sh'),
        '700',
        'blade_prepare_script',
        True,
    ),
]

deployment_files = {
    'quickstart': (BLADE_FILES, QUICKSTART_MANAGEMENT_NODE_FILES),
    'bare': (BLADE_FILES, BARE_MANAGEMENT_NODE_FILES),
    'quadlet': (BLADE_FILES, QUADLET_MANAGEMENT_NODE_FILES),
}
