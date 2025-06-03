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
"""Layer implementation module for the openchami application.

"""
from tempfile import NamedTemporaryFile

from vtds_base import (
    info_msg,
    ContextualError,
    render_template_file,
)
from vtds_base.layers.application import ApplicationAPI
from . import DEPLOY_FILES


class Application(ApplicationAPI):
    """Application class, implements the openchami application layer
    accessed through the python Application API.

    """
    def __init__(self, stack, config, build_dir):
        """Constructor, stash the root of the platfform tree and the
        digested and finalized application configuration provided by the
        caller that will drive all activities at all layers.

        """
        self.__doc__ = ApplicationAPI.__doc__
        self.config = config.get('application', None)
        if self.config is None:
            raise ContextualError(
                "no application configuration found in top level configuration"
            )
        self.stack = stack
        self.build_dir = build_dir
        self.prepared = False

    def __validate_host_info(self):
        """Run through the 'host' configuration and make sure it is
        all valid and consistent.

        """
        cluster = self.stack.get_cluster_api()
        virtual_networks = cluster.get_virtual_networks()
        virtual_nodes = cluster.get_virtual_nodes()
        host = self.config.get('host', None)
        if host is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'host' information block"
            )
        if not isinstance(host, dict):
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "invalid 'host' information block "
                "(should be a dictionary not a %s)" % str(type(host))
            )
        host_net = host.get('network', None)
        if host_net is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'network' element in the 'host' information block"
            )
        if host_net not in virtual_networks.network_names():
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "unknown network name '%s' in the 'network' element of "
                "the 'host' information block (available networks are: "
                "%s)" % (host_net, virtual_networks.network_names())
            )
        host_node_class = host.get('node_class', None)
        if host_node_class is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'node_class' element in the 'host' information block"
            )
        if host_node_class not in virtual_nodes.node_classes():
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "unknown node class name '%s' in the 'node_class' element of "
                "the 'host' information block "
                "(available node classes are %s)" % (
                    host_node_class, virtual_nodes.node_classes
                )
            )

    def __validate_discovery_networks(self):
        """Run through the 'discovery_networks' configuration and make
        sure it all networks are well formed.

        """
        discovery_networks = self.config.get('discovery_networks', None)
        if discovery_networks is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'discovery_networks' information block"
            )
        if not isinstance(discovery_networks, dict):
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "invalid 'discovery_networks' information block (should "
                "be a dictionary not a %s)" % str(type(discovery_networks))
            )
        if not discovery_networks:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "networks described in its 'discovery_networks' "
                "information block"
            )
        # Look for improperly formed discovery_networks. The
        # consolidate step has already weeded out discovery networks
        # whose network name is invalid.
        for name, network in discovery_networks.items():
            network_name = network.get('network_name', None)
            network_cidr = network.get('network_cidr', None)
            if network_name is None and network_cidr is None:
                raise ContextualError(
                    "validation error: OpenCHAMI layer configuration "
                    "discovery network '%s' has neither a network name "
                    "nor a network CIDR specified" % name
                )
            if network_name is not None and network_cidr is not None:
                raise ContextualError(
                    "validation error: OpenCHAMI layer configuration "
                    "discovery network '%s' has both a network name "
                    "and a network CIDR specified, only one is allowed "
                    "at a time" % name
                )

    def __template_data(self):
        """Return a dictionary for use in rendering files to be
        shipped to the host node(s) for deployment based on the
        Application layer configuration.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()
        virtual_networks = cluster.get_virtual_networks()
        host = self.config.get('host', {})
        host_network = host['network']
        host_node_class = host['node_class']
        addressing = virtual_nodes.node_class_addressing(
            host_node_class, host_network
        )
        macs = addressing.addresses('AF_PACKET')
        discovery_networks = self.config.get('discovery_networks', {})
        template_data = {
            # Find a way to generate and install these instead of hard
            # coding them. For now they are hard coded into RIE so we
            # need match them here.
            'host_node_class': host_node_class,
            'emulator_username': 'root',
            'emulator_password': 'root_password',
            'discovery_networks': [
                {
                    'cidr': (
                        virtual_networks.ipv4_cidr(network['network_name'])
                        if network['network_name'] is not None else
                        network['network_cidr']
                    ),
                    'name': name,
                }
                for name, network in discovery_networks.items()
            ],
            'hosts': [
                {
                    'host_instance': instance,
                    'host_mac': macs[instance],
                }
                for instance in range(0, len(macs))
            ]
        }
        print("template_date = \n%s" % str(template_data))
        return template_data

    def __deploy_files(self, connections, files):
        """Copy files to the blades or nodes connected in
        'connections' based on the manifest and run the appropriate
        deployment script(s).

        """
        template_data = self.__template_data()
        for source, dest, mode, tag, run in files:
            info_msg(
                "copying '%s' to host-node node(s) '%s'" % (
                    source, dest
                )
            )
            with NamedTemporaryFile() as tmpfile:
                # ERIC TAKE THIS OUT ONCE vtds-base VSHA-651 IS MERGED AND
                # TAGGED
                #
                # pylint: disable=too-many-function-args
                render_template_file(source, template_data, tmpfile.name)
                connections.copy_to(
                    tmpfile.name, dest,
                    recurse=False, logname="upload-application-%s-to-%s" % (
                        tag, 'host-node'
                    )
                )
            cmd = "chmod %s %s;" % (mode, dest)
            info_msg(
                "chmod'ing '%s' to %s on host-node node(s)" % (dest, mode)
            )
            connections.run_command(cmd, "chmod-file-%s-on" % tag)
            if run:
                cmd = "%s {{ node_class }} {{ instance }}" % dest
                info_msg("running '%s' on host-node node(s)" % cmd)
                connections.run_command(cmd, "run-%s-on" % tag)

    def consolidate(self):
        # Run through and remove any discovery network whose network
        # name is not defined in the cluster configuration.
        virtual_networks = self.stack.get_cluster_api().get_virtual_networks()
        available_networks = virtual_networks.network_names()
        discovery_networks = self.config.get('discovery_networks', {})
        filtered_discovery_networks = {
            name: network
            for name, network in discovery_networks.items()
            if network.get('network_name', None) is None or
            network['network_name'] in available_networks
        }
        self.config['discovery_networks'] = filtered_discovery_networks

    def prepare(self):
        self.prepared = True
        print("Preparing vtds-application-openchami")

    def validate(self):
        if not self.prepared:
            raise ContextualError(
                "cannot validate an unprepared application, "
                "call prepare() first"
            )
        print("Validating vtds-application-openchami")
        self.__validate_host_info()
        self.__validate_discovery_networks()

    def deploy(self):
        if not self.prepared:
            raise ContextualError(
                "cannot deploy an unprepared application, call prepare() first"
            )
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        with virtual_nodes.ssh_connect_nodes(['host_node']) as connections:
            self.__deploy_files(connections, DEPLOY_FILES)

    def remove(self):
        if not self.prepared:
            raise ContextualError(
                "cannot deploy an unprepared application, call prepare() first"
            )
        print("Removing vtds-application-openchami")
