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
from copy import deepcopy
from tempfile import NamedTemporaryFile
from uuid import uuid4

from vtds_base import (
    info_msg,
    warning_msg,
    ContextualError,
    render_template_file,
)
from vtds_base.layers.application import ApplicationAPI
from vtds_base.layers.cluster import NodeSSHConnectionSetBase
from . import deployment_files


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
        self.deploy_mode = None
        self.deployment_files = None
        self.tpl_data = None
        self.tpl_data_calls = {
            'quadlet': self.__tpl_data_quadlet,
            'bare': self.__tpl_data_bare,
        }

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
            redfish_username = network.get('redfish_username', None)
            redfish_password = network.get('redfish_password', None)
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
            if redfish_username is None:
                raise ContextualError(
                    "validation error: OpenCHAMI layer configuration "
                    "discovery network '%s' has no RedFish username" % name
                )
            if redfish_password is None:
                raise ContextualError(
                    "validation error: OpenCHAMI layer configuration "
                    "discovery network '%s' has no RedFish password" % name
                )

    def __bmc_mappings(self):
        """Return a list of dictionaries echo of which contains the
        xname and address of a Virtual Blade, for every Virtual Blade
        connected to a discovery network and for every address family
        each blade supports. For example, if there are 5 Virtual
        Blades connected to a discovery network, and each has an
        AF_INET (IPv4) address and an AF_PACKET (MAC) address, there
        would be two entries in the list per blade: one containing the
        xname and IPv4 address and the other containing the same xname
        and the MAC address. Hence a total of 10 entries in the list.

        """
        virtual_networks = self.stack.get_cluster_api().get_virtual_networks()
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        # Get the list of names of discovery networks
        discovery_net_names = [
            network['network_name']
            for _, network in self.config.get('discovery_networks', {}).items()
            if network.get('network_name', None)
        ]
        # Get the xname lists for each of the blade classes defined in
        # the configuration.
        blade_class_xnames = {
            blade_class: virtual_blades.application_metadata(blade_class).get(
                'xnames', []
            )
            for blade_class in virtual_blades.blade_classes()
        }
        # Get a blade class to list of Adressing objects map for all
        # blade classes that have xnames listed for them
        blade_class_addressing = {
            blade_class: [
                virtual_networks.blade_class_addressing(blade_class, net_name)
                for net_name in discovery_net_names
            ]
            for blade_class, xnames in blade_class_xnames.items()
            if xnames
        }
        # Get a blade class name to connected instances set mapping
        blade_instances = {
            # Map the blade class to the set of unique instances from
            # all of the networks on which that blade class has
            # connected instances. NOTE: this is a set comprehension
            # not a list comprehension, since there can be multiple
            # references to a single instance.
            blade_class: {
                instance
                for addressing in blade_class_addressing[blade_class]
                for instance in addressing.instances()
            }
            for blade_class in blade_class_addressing.keys()
        }
        # Get the mapping of (blade_class, instance) to xname from the
        # blade_class_xnames. If there is an instance without a
        # matching xname (i.e. the list of xnames is too short) skip
        # it.
        blade_xnames = {
            (blade_class, instance): blade_class_xnames[blade_class][instance]
            for blade_class in blade_class_addressing.keys()
            for instance in blade_instances[blade_class]
            if instance < len(blade_class_xnames[blade_class])
        }
        # Get the mapping of (blade_class, instance) to list of
        # addresses from blade_class_addressing. Note that this is all
        # addresses in all address families on each discovery network,
        # not just IPv4 addresses.
        blade_addresses = {
            (blade_class, instance): [
                addressing.address(family, instance)
                for addressing in blade_class_addressing[blade_class]
                for family in addressing.address_families()
                # It is possible for addressing.address() to return
                # None, skip those...
                if addressing.address(family, instance) is not None
            ]
            for (blade_class, instance) in blade_xnames
        }
        # Finally, return the address to xname mapping for all of the
        # blade instances using blade_addresses and blade_xnames
        return [
            {
                'addr': address,
                'xname': xname,
            }
            for (blade_class, instance), xname in blade_xnames.items()
            for address in blade_addresses[(blade_class, instance)]
        ]

    @staticmethod
    def __clean_rie_service(rie_service):
        """Remove the 'delete' field (if any) from the supplied
        'rie_service' description and return the result
        """
        if 'delete' in rie_service:
            rie_service.pop('delete')
        return rie_service

    def __tpl_data(self):

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
        # Remove deleted services and clean out the delete field from
        # all RIE services so that it doesn't leak into the template
        # files.
        rie_services = {
            rie_name: self.__clean_rie_service(rie_service)
            for rie_name, rie_service in deepcopy(
                    self.config.get('rie_services', {})
            ).items()
            if not rie_service.get('delete', 'False')
        }
        addressing = virtual_nodes.node_class_addressing(
            host_node_class, host_network
        )
        if addressing is None:
            raise ContextualError(
                "unable to find addressing for the host network '%s' "
                "configured on the host node class '%s' - check your "
                "application configuration and see that it matches your "
                "cluster configuration." % (host_network, host_node_class)
            )
        macs = addressing.addresses('AF_PACKET')
        discovery_networks = self.config.get('discovery_networks', {})
        bmc_mappings = self.__bmc_mappings()
        tpl_data = {
            'host_node_class': host_node_class,
            'discovery_networks': [
                {
                    'cidr': (
                        virtual_networks.ipv4_cidr(network['network_name'])
                        if network['network_name'] is not None else
                        network['network_cidr']
                    ),
                    'external': network['network_name'] is not None,
                    'name': name,
                    'redfish_username': network['redfish_username'],
                    'redfish_password': network['redfish_password'],
                }
                for name, network in discovery_networks.items()
            ],
            'hosts': [
                {
                    'host_instance': instance,
                    'host_mac': macs[instance],
                }
                for instance in range(0, len(macs))
            ],
            'rie_services': rie_services,
            'bmc_mappings': bmc_mappings,
        }
        return tpl_data

    def __bmc_addressing_by_node_class(self, node_classes):
        """Generate a node-class name to Virtual Blade addressing
        dictionary based on discovery networks and node-class host
        blade information.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()
        virtual_networks = cluster.get_virtual_networks()
        # Get the list of discovery Virtual Network names where
        # Virtual Blades hosting BMC services may live so we can get
        # the BMC information for each node.
        discovery_network_names = [
            network['network_name']
            for _, network in self.config.get('discovery_networks', {}).items()
            if network.get('network_name', None) is not None
        ]
        # Get the addressing for all of the BMC Virtual Blade classes
        # hosting Virtual nodes. If the BMC for a given node class is
        # not connected to a given network, the addressing on that
        # network for the BMC will be None, so we should skip it. If
        # the BMC for a given node class is one more than one
        # discovery network, it should be okay just to take the last
        # one we find.
        bmc_addressing = {
            node_class: virtual_networks.blade_class_addressing(
                virtual_nodes.node_host_blade_info(
                    node_class
                )['blade_class'],
                net_name
            )
            for node_class in node_classes
            for net_name in discovery_network_names
            if virtual_networks.blade_class_addressing(
                virtual_nodes.node_host_blade_info(
                    node_class
                )['blade_class'],
                net_name
            ) is not None
        }
        # Check for and warn about any node_class that has a BMC
        # Virtual Blade that is not connected to a Discovery Network,
        # since those will be undiscoverable.
        disconnected = [
            node_class
            for node_class in node_classes
            if node_class not in bmc_addressing
        ]
        if disconnected:
            warning_msg(
                "the following node classes appear to have host Virtual "
                "Blades that are not connected to a discovery network "
                "and will not be discovered: '%s'" % "', '".join(disconnected)
            )
        return bmc_addressing

    def __nid_from_class_instance(self, classes, class_name, instance):
        """Calculate a NID from a list of node class names, the node's
        node class name and the node class instance number.

        """
        # Sort the node_classes list so we get repeatable results from
        # the same list of node classes whatever order they are in.
        classes.sort()

        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        if instance >= virtual_nodes.node_count(class_name):
            # Invalid instance number bail out
            raise ContextualError(
                "instance number %d is out of range for node class '%s' which "
                "has only %d instances configured" % (
                    instance, class_name, virtual_nodes.node_count(class_name)
                )
            )
        base_nid = 1
        for current_class in classes:
            if class_name == current_class:
                return base_nid + instance
            base_nid += virtual_nodes.node_count(current_class)
        raise ContextualError(
            "unrecognized node class '%s' requested from a node class list "
            "containing '%s'" % (
                class_name, "', '".join(classes)
            )
        )

    def __node_classes_by_role(self, role):
        """Get the list of node classes within the specified
        'role'. The 'role' can be 'managed' or 'management'. A node
        class without a specified role is assumed to be 'management'.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()
        return [
            node_class
            for node_class in virtual_nodes.node_classes()
            if virtual_nodes.application_metadata(node_class).get(
                    'node_role', "management"
            ) == role
        ]

    @staticmethod
    def __formatted_str_list(str_list):
        """Format a friendly string for use with errors that lists
        strings in a comma separated and quoted with an 'and'
        form. Example: "'a', 'b' and 'c'"

        """
        return (
            "%s, and '%s'" %
            (
                ", ".join(
                    [
                        "'%s'" % mode
                        for mode in str_list
                    ][:-1]
                ),
                str_list[-1]
            )
            if len(str_list > 1) else '%s' % str_list[0]
            if str_list else ""
        )

    def __tpl_data_quadlet_nodes(self):
        """Construct the 'nodes' element of the quadlet system
        template data.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()

        # We are going to go through the node classes and their
        # instances assigning NID values to each node. To make this
        # repeatable on a given config, sort the node class names so
        # they come up in the same order every time.
        managed_node_classes = self.__node_classes_by_role('managed')
        bmc_addressing = self.__bmc_addressing_by_node_class(
            managed_node_classes
        )
        bmc_instances = {
            (node_class, instance): (
                int(instance / virtual_nodes.node_host_blade_info(
                    node_class
                )['instance_capacity'])
            )
            for node_class in bmc_addressing.keys()
            for instance in range(0, virtual_nodes.node_count(node_class))
        }
        return [
            {
                # Name here will be the node's name (i.e. domain name,
                # not host name) which is also its xname
                'name': virtual_nodes.node_node_name(node_class, instance),
                # Hostname here will be the node's host name
                'hostname': virtual_nodes.node_hostname(node_class, instance),
                # NIDs are computed by sorting the node classes then
                # running through each node class and counting its
                # members. This is deterministic for a given config
                # but not configurable.
                'nid': self.__nid_from_class_instance(
                    managed_node_classes, node_class, instance
                ),
                # We forced the node name of the node to be its xname
                # during consolidate(), use the node name here...
                'xname': virtual_nodes.node_node_name(node_class, instance),
                'bmc_mac': addressing.address(
                    'AF_PACKET', bmc_instances[(node_class, instance)]
                ),
                'bmc_ip':  addressing.address(
                    'AF_INET', bmc_instances[(node_class, instance)]
                ),
                'cluster_net_interface': (
                    virtual_nodes.application_metadata(node_class).get(
                        'cluster_net_interface', ""
                    )
                ),
                'management_net_interface': (
                    virtual_nodes.application_metadata(node_class).get(
                        'management_net_interface', ""
                    )
                ),
                'node_class': node_class,
                'node_group': (
                    virtual_nodes.application_metadata(node_class).get(
                        'node_group', node_class
                    )
                ),
                'interfaces': [
                    {
                        'network_name': net_name,
                        'mac_addr': virtual_nodes.node_class_addressing(
                            node_class, net_name
                        ).address('AF_PACKET', instance),
                        'ip_addrs': [
                            {
                                'name': net_name,
                                'ip_addr': virtual_nodes.node_class_addressing(
                                    node_class, net_name
                                ).address('AF_INET', instance),
                            },
                        ]
                    }
                    for net_name in virtual_nodes.network_names(node_class)
                ],
            }
            for node_class, addressing in bmc_addressing.items()
            for instance in range(0, virtual_nodes.node_count(node_class))
        ]

    def __tpl_data_quadlet_managed_macs(self):
        """Get the list of MAC addresses for Manaaged Nodes on their
        networks.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()
        virtual_networks = cluster.get_virtual_networks()
        return [
            mac
            for node_class in virtual_nodes.node_classes()
            for net_name in virtual_networks.network_names()
            for mac in (
                    virtual_nodes.node_class_addressing(
                        node_class, net_name
                    ).addresses('AF_PACKET')
                    if virtual_nodes.node_class_addressing(
                            node_class, net_name
                    ) is not None else []
            )
        ]

    def __tpl_data_quadlet_hosting_cfg(self):
        """Get the configuration for hosting nodes under management by
        OpenCHAMI on this system. This includes the management network
        IP setup, the management node IP and FQDN within the cluster,
        whether or not libvirt hosting of a "Compute Node" on the
        Management node is to be allowed (i.e. the tutorial use case),
        and, if so, what the libvirt network setup is, and so forth.

        XXX - these settings are hardcoded temporarily to allow them
        to be used in templates. They need to be derived from config.

        """
        return {
            'management': {
                'enable': True,
                'net_head_host': "demo",
                'net_head_domain': "openchami.cluster",
                'net_head_fqdn': "demo.openchami.cluster",
                'net_head_ip': "10.2.1.2",
                'cluster_net_dhcp_start': "10.2.1.32",
                'cluster_net_dhcp_end': "10.2.1.254",
                'cluster_net_cidr': "10.2.1.0/24",
                'nat_if_cidr': "10.255.1.1/32",
                # The IP address where the head-node's FQDN and
                # external DNS are configured: normally the management
                # network address of the first Virtual Blade hosting a
                # management node.
                'net_head_dns_server': "10.234.0.1",
                'upstream_dns_server': "169.254.169.254",
                'prefix_len': "24",
                'netmask': "255.255.255.0",
            },
            'cohost': {
                'enable': False,
                'net_head_host': "cohost_gw",
                'net_head_domain': "openchami.cluster",
                'net_head_fqdn': "cohost_gw.openchami.cluster",
                'net_head_ip': "172.16.0.254",
                'prefix_len': "24",
                'netmask': "255.255.255.0",
            },
        }

    def __tpl_data_quadlet(self):
        """Construct the template data dictionary used for building
        templated deployment files for the Quadlet based mode of
        deployment.

        """
        tpl_data = self.__tpl_data()
        tpl_data['nodes'] = self.__tpl_data_quadlet_nodes()
        tpl_data['managed_macs'] = self.__tpl_data_quadlet_managed_macs()
        tpl_data['hosting_config'] = self.__tpl_data_quadlet_hosting_cfg()
        return tpl_data

    def __tpl_data_bare(self):
        """Construct the template data dictionary used for building
        templated deployment files for the Bare System mode of
        deployment.

        """
        return self.__tpl_data()

    def __choose_tpl_data(self):
        """Pick the appropriate template data for the configured mode of
        """
        try:
            return self.tpl_data_calls[self.deploy_mode]()
        except KeyError as err:
            raise ContextualError(
                "unrecognized deployment mode '%s' configured - recognized "
                "modes are: %s" % (
                    self.deploy_mode,
                    self.__formatted_str_list(
                        list(self.tpl_data.keys())
                    )
                )
            )from err

    def __choose_deployment_files(self):
        """Based on the configured deployment mode, pick the correct
        set of blade and management node deployment files.

        """
        try:
            return deployment_files[self.deploy_mode]
        except KeyError as err:
            raise ContextualError(
                "unrecognized deployment mode '%s' configured - recognized "
                "modes are: %s" % (
                    self.deploy_mode,
                    self.__formatted_str_list(
                        list(self.deployment_files.keys())
                    )
                )
            ) from err

    def __deploy_files(self, connections, files, target='host-node'):
        """Copy files to the blades or nodes connected in
        'connections' based on the manifest and run the appropriate
        deployment script(s).

        """
        for source, dest, mode, tag, run in files:
            info_msg(
                "copying '%s' to host-node node(s) '%s'" % (
                    source, dest
                )
            )
            with NamedTemporaryFile() as tmpfile:
                render_template_file(source, self.tpl_data, tmpfile.name)
                connections.copy_to(
                    tmpfile.name, dest,
                    recurse=False, logname="upload-application-%s-to-%s" % (
                        tag, target
                    )
                )
            cmd = "chmod %s %s;" % (mode, dest)
            info_msg(
                "chmod'ing '%s' to %s on host-node node(s)" % (dest, mode)
            )
            connections.run_command(cmd, "chmod-file-%s-on" % tag)
            if run:
                if isinstance(connections, NodeSSHConnectionSetBase):
                    cmd = "%s {{ node_class }} {{ instance }}" % dest
                    info_msg("running '%s' on host-node node(s)" % cmd)
                else:
                    cmd = "%s {{ blade_class }} {{ instance }}" % dest
                    info_msg("running '%s' on host-blade(s)" % cmd)
                connections.run_command(cmd, "run-%s-on" % tag)

    def __set_node_xnames(self):
        """Compute and fill in XNAME node names for all nodes on
        Virtual Blades that host managed nodes. Managed node xnames
        come first to keep their node numbering consistent on all
        blades. Non-managed nodes come last, since it is less
        important to be able to predict their node numbering.

        """
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        node_classes = (
            self.__node_classes_by_role('managed') +
            self.__node_classes_by_role('management')
        )
        host_blades = {
            node_class: virtual_nodes.node_host_blade_info(node_class)
            for node_class in node_classes
        }

        # Collect a set of unique blade classes that are actually in use...
        blade_classes = {
            blade_info['blade_class']
            for _, blade_info in host_blades.items()
        }

        # Set up a blade_class to XNAME list dictionary for all of the
        # blade classes we are going to see.
        blade_xnames = {
            blade_class: virtual_blades.application_metadata(blade_class).get(
                'xnames', []
            )
            # Use a set here to get one instance of each host blade class
            for blade_class in blade_classes
        }

        # Initialize a dictionary of blade xnames to the next available
        # node number on the blade for each blade in the list of
        # virtual blades hosting nodes on the system.
        xname_slots = {
            xname: 0
            for _, xnames in blade_xnames.items()
            for xname in xnames
        }
        # Compute the node xnames for each node and register it with
        # the cluster layer.
        for node_class, blade_info in host_blades.items():
            bl_xnames = blade_xnames[blade_info['blade_class']]
            capacity = int(blade_info['instance_capacity'])
            for instance in range(0, virtual_nodes.node_count(node_class)):
                bl_index = int(instance / capacity)
                if bl_index > len(bl_xnames):
                    raise ContextualError(
                        "not enough blade xnames are configured for virtual "
                        "blade class '%s' to host %d instances of node class "
                        "'%s', please update the provider configuration with "
                        "additional blade xnames" % (
                            blade_info['blade_class'],
                            virtual_nodes.node_count(node_class),
                            node_class
                        )
                    )
                blade_xname = bl_xnames[bl_index]
                node_number = xname_slots[blade_xname]
                xname_slots[blade_xname] += 1
                node_xname = "%sn%d" % (blade_xname, node_number)
                virtual_nodes.set_node_node_name(
                    node_class, instance, node_xname
                )

    def consolidate(self):
        # Before preparing to ship files, make sure that the node
        # xnames have been installed in the cluster layer for us to
        # use.
        self.__set_node_xnames()

        # Set up for preparing and shipping deployment files
        #
        # Get the deployment mode from the config. Default to 'quadlet'.
        self.deploy_mode = (
            self.config.get('deployment', {}).get('mode', 'quadlet')
        )
        self.deployment_files = self.__choose_deployment_files()
        self.tpl_data = self.__choose_tpl_data()

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
        # Before handing the filtered discovery networks back, for any
        # that has a None redfish_password setting, conjur a password
        # for it...
        for _, network in discovery_networks.items():
            password = network.get('redfish_password', None)
            network['redfish_password'] = (
                password if password is not None else str(uuid4())
            )
        self.config['discovery_networks'] = filtered_discovery_networks

        # Clean out RIE servers that are marked for deletion and clean
        # out the 'delete' key value pair from all RIE servers
        self.config['rie_services'] = {
            name: {
                key: value
                for key, value in service.items() if key != 'delete'
            }
            for name, service in self.config.get('rie_services', {}).items()
            if not service.get('delete', False)
        }

    def prepare(self):
        self.prepared = True

    def validate(self):
        if not self.prepared:
            raise ContextualError(
                "cannot validate an unprepared application, "
                "call prepare() first"
            )
        self.__validate_host_info()
        self.__validate_discovery_networks()

    def deploy(self):
        if not self.prepared:
            raise ContextualError(
                "cannot deploy an unprepared application, call prepare() first"
            )
        blade_files, management_node_files = self.deployment_files
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        with virtual_blades.ssh_connect_blades() as connections:
            self.__deploy_files(connections, blade_files, 'host-blade')
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        host_node_class = self.config.get('host', {}).get('node_class')
        with virtual_nodes.ssh_connect_nodes([host_node_class]) as connections:
            self.__deploy_files(connections, management_node_files)

    def remove(self):
        if not self.prepared:
            raise ContextualError(
                "cannot deploy an unprepared application, call prepare() first"
            )
