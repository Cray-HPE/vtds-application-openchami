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

TESTING_DIR_PATH = path_join(
    dirname(__file__),
    'cluster_tests'
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


def test_file_source(filename):
    """Translate a filename into a path in the python module where a test
    file can be found.

    """
    return path_join(TESTING_DIR_PATH, filename)


def test_file_dest(filename):
    """Translate a filename or relative path into a full path on the
    remote host that is the 'root' home directory and in the 'cluster_tests'
    sub-tree.

    """
    return path_join(separator, "root", "cluster_tests", filename)


# Templated files to be deployed to the management node: (source, dest,
# mode, tag, run)
#
# Management node files for the bare system deployment mode
BARE_MANAGEMENT_NODE_FILES = [
    (
        template('common/cluster_overlay.yaml'),
        home('cluster_overlay.yaml'),
        '600',
        'cluster_configuration_overlay',
        False,
    ),
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
        test_file_source('suppressed_test.sh'),
        test_file_dest('suppressed_test.sh'),
        '755',
        'suppressed_test_action_script',
        False,
    ),
    (
        test_file_source('driver.sh'),
        test_file_dest('driver.sh'),
        '755',
        'main_test_driver_script',
        False,
    ),
    (
        template('common/cluster_overlay.yaml'),
        home('cluster_overlay.yaml'),
        '600',
        'cluster_configuration_overlay',
        False,
    ),
    (
        template('quadlet/prep_setup.sh'),
        home('prep_setup.sh'),
        '644',
        'node_prepare_setup_library',
        False,
    ),
    (
        template('quadlet/OpenCHAMI-Deploy.sh'),
        home('OpenCHAMI-Deploy.sh'),
        '755',
        'openchami_deployment_script',
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
        template('blade/bmc_info.json'),
        home('bmc_info.json'),
        '600',
        'blade_BMC_settings',
        False,
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
    'bare': (BLADE_FILES, BARE_MANAGEMENT_NODE_FILES),
    'quadlet': (BLADE_FILES, QUADLET_MANAGEMENT_NODE_FILES),
}
