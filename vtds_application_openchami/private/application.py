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
"""Layer implementation module for the openchami application.

"""
from ipaddress import ip_network
import re
from tempfile import NamedTemporaryFile

from passlib.hash import md5_crypt
from passlib import pwd

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
        host_node_name = host.get('node_name', None)
        if host_node_name is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'node_name' element in the 'host' information block"
            )
        if not isinstance(host_node_name, str):
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "invalid 'node_name' value in the host information block "
                "(should be a string not a %s)" % str(type(host_node_name))
            )

    def __validate_cluster_info(self):
        """Run through the 'cluster' configuration and make sure it is
        all valid and consistent.

        """
        domain_re = re.compile(
            r"^(?!-)(?:[a-zA-Z0-9-]{1,63}\.)+[a-zA-Z]{2,63}$"
        )
        cluster_config = self.config.get('cluster', None)
        if cluster_config is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'cluster' information block"
            )
        if not isinstance(cluster_config, dict):
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has an "
                "invalid 'cluster' information block "
                "(should be a dictionary not a %s)" % str(type(cluster_config))
            )
        domain_name = cluster_config.get('domain_name', None)
        if domain_name is None:
            raise ContextualError(
                "validation error: OpenCHAMI layer configuration has no "
                "'domain_name' element in the 'cluster' information block"
            )
        if not isinstance(domain_name, str):
            raise ContextualError(
                "validation error: OpenCHAMI layer cluster configuration "
                "has an invalid 'domain_name' (should be a string not "
                "a %s)" % str(type(domain_name))
            )
        if not domain_re.match(domain_name):
            raise ContextualError(
                "validation error: OpenCHAMI layer cluster configuration "
                "has a non-conforming 'domain_name' ['%s']" % domain_name
            )
        _ = self.__cluster_network(validate=True)
        _ = self.__management_network(validate=True)
        _ = self.__cluster_net_coredhcp()
        _ = self.__dns_config()

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

    def __tagged_network(self, tag, validate):
        """Find the first network with a field in its
           application_metadata of the form '<tag>: true' and return
           the name of that network. If 'validate' is true, raise
           errors and warnings based on error conditions found. Since
           we run a 'validate' pass on data, other callers may specify
           'validate' as false to reduce verbosity of warning
           messages.

        """
        cluster = self.stack.get_cluster_api()
        virtual_networks = cluster.get_virtual_networks()
        available_networks = virtual_networks.network_names()
        tagged_networks = [
            network_name
            for network_name in available_networks
            if virtual_networks.application_metadata(
                    network_name
            ).get(tag, False)
        ]
        if len(tagged_networks) < 1 and validate:
            raise ContextualError(
                "there is no Virtual Network with the '%s: true' tag "
                "network in Virtual Network application metadata. "
                "Please edit your Cluster Layer Virtual Network "
                "configurations and add a '%s: true' "
                "specifier to application metadata in one of the "
                "Virtual Network descriptions." % (tag, tag)
            )
        if len(tagged_networks) > 1 and validate:
            warning_msg(
                "more than one network %s with the '%s: true' tag "
                "network in the Cluster Layer Virtual Network "
                "application metadata. At present only one such "
                "network is supported, so the first one found '%s' "
                "will be used." % (
                    str(tagged_networks), tag, tagged_networks[0]
                )
            )
        return tagged_networks[0]

    def __cluster_network(self, validate=False):
        """Find the first Virtual Network with the
        'cluster_network: true' tag
        in its application metadata and return its name.

        """
        return self.__tagged_network('cluster_network', validate)

    def __management_network(self, validate=False):
        """Find the first Virtual Network with the
        'management_network: true' tag
        in its application metadata and return its name.

        """
        return self.__tagged_network('management_network', validate)

    def __cluster_net_coredhcp(self):
        """Retrieve the cluster network coredhcp configuration from the
        Virtual Network application metadata in the vTDS Cluster Layer
        for OpenCHAMI.
        """
        cluster_net = self.__cluster_network()
        cluster = self.stack.get_cluster_api()
        virtual_networks = cluster.get_virtual_networks()
        metadata = virtual_networks.application_metadata(cluster_net)
        coredhcp = metadata.get('coredhcp', None)
        if coredhcp is None:
            raise ContextualError(
                "the designated cluster network ('%s') has no "
                "coredhcp configuration defined in its vTDS "
                "Cluster Layer Virtual Network application "
                "metadata for OpenCHAMI." % cluster_net
            )
        if not isinstance(coredhcp, dict):
            raise ContextualError(
                "the designated cluster network ('%s') has an "
                "invalid coredhcp configuration defined in its "
                "vTDS Cluster Layer Virtual Network application "
                "metadata for OpenCHAMI (it should be a "
                "dictionary not "
                "a %s)" % (cluster_net, str(type(coredhcp)))
            )
        pool = coredhcp.get('pool', None)
        if pool is None:
            raise ContextualError(
                "the designated cluster network ('%s') has no "
                "address range 'pool' defined for coredhcp "
                "in its vTDS Cluster Layer Virtual Network "
                "application metadata for "
                "OpenCHAMI." % cluster_net
            )
        if not isinstance(pool, dict):
            raise ContextualError(
                "the designated cluster network ('%s') has an "
                "invalid address range 'pool' for coredhcp in its "
                "vTDS Cluster Layer Virtual Network application "
                "metadata for OpenCHAMI (it should be a "
                "dictionary not "
                " a %s)" % (cluster_net, str(type(pool)))
            )
        if pool.get('start', None) is None:
            raise ContextualError(
                "the designated cluster network ('%s') has no "
                "address range 'pool' 'start' addrtess defined "
                "for coredhcp in its vTDS Cluster Layer Virtual"
                " Network application metadata for "
                "OpenCHAMI." % cluster_net
            )
        if pool.get('end', None) is None:
            raise ContextualError(
                "the designated cluster network ('%s') has no "
                "address range 'pool' 'start' addrtess defined "
                "for coredhcp in its vTDS Cluster Layer Virtual"
                " Network application metadata for "
                "OpenCHAMI." % cluster_net
            )
        return coredhcp

    def __dns_config(self):
        """Get the DNS configuration for site and public DNS servers
        from the configuration.

        """
        dns = self.config.get('dns', None)
        if dns is None:
            raise ContextualError(
                "no DNS configuration block exists in the application "
                "layer configuration for OpenCHAMI"
            )
        if not isinstance(dns, dict):
            raise ContextualError(
                "the DNS configuration block in the application "
                "layer configuration for OpenCHAMI is invalid "
                "(should be a dictionary block not a '%s')" % str(type(dns))
            )
        if dns.get('site', None) is None:
            raise ContextualError(
                "no 'site' value is configured in the DNS configuration "
                "block in the application layer configuration for OpenCHAMI. "
                "Use the blade host network IP address for the management "
                "node for this."
            )
        if dns.get('public', None) is None:
            raise ContextualError(
                "no 'public' value is configured in the DNS configuration "
                "block in the application layer configuration for OpenCHAMI. "
                "Use either the provider's DNS server if one exists or known "
                "good public DNS server IP address for this."
            )
        return dns

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

    def __tpl_data(self):

        """Template Data Collector

        Return a dictionary for use in rendering files to be
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
            'bmc_mappings': bmc_mappings,
        }
        return tpl_data

    def __bmc_xnames_by_node_class(self, node_classes):
        """Generate a node-class name to Virtual Blade XNAME list
        dictionary based on node-class host blade information.

        """
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        # Get the XNAME lists for all of the BMC Virtual Blade classes
        # hosting Virtual nodes.
        bmc_xnames = {
            node_class: virtual_blades.application_metadata(
                virtual_nodes.node_host_blade_info(
                    node_class
                )['blade_class']
            ).get('xnames', [])
            for node_class in node_classes
            if virtual_blades.application_metadata(
                    virtual_nodes.node_host_blade_info(
                        node_class
                    )['blade_class']
            ).get('xnames', [])
        }
        # Check for and warn about any node_class that has no BMC
        # XNAMEs assigned to it because those will not work in
        # discovery.
        broken = [
            node_class
            for node_class in node_classes
            if node_class not in bmc_xnames
        ]
        if broken:
            warning_msg(
                "the following node classes appear to have host Virtual "
                "Blades that have no XNAMEs defined in application metadata "
                "and will fail discovery: '%s'" % "', '".join(broken)
            )
        return bmc_xnames

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
            if len(str_list) > 1 else '%s' % str_list[0]
            if str_list else ""
        )

    def __tpl_data_quadlet_bmcs(self):
        """
        Template Data Collector

        Construct the 'bmcs' element of the quadlet system template
        data.

        """
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        virtual_networks = self.stack.get_cluster_api().get_virtual_networks()
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        # Get the list of managed node classes because we need the
        # blade classes that host the ones that have non-zero counts.
        node_classes = self.__node_classes_by_role('managed')
        # Get the list of blade classes that are actually in use (i.e. they
        # host actual managed nodes)
        blade_classes = [
            virtual_nodes.node_host_blade_info(node_class)['blade_class']
            for node_class in node_classes
            if virtual_nodes.node_count(node_class) > 0
        ]
        blade_class_xnames = {
            blade_class: virtual_blades.application_metadata(blade_class).get(
                'xnames', []
            )
            for blade_class in blade_classes
        }
        discovery_networks = self.config.get('discovery_networks', {})
        # Get the blade to blade count mapping for all blade classes
        # that have 1 or more instances. This gathers the counts and
        # makes sure we only include blades that actually exist from
        # here on in.
        blade_counts = {
            blade_class: virtual_blades.blade_count(blade_class)
            for blade_class in blade_classes
            if virtual_blades.blade_count(blade_class) > 0
        }
        # Get all of the BMC information for blade instances on all of
        # their connected discovery networks.
        blade_info = {
            (blade_class, instance): {
                'xname': blade_class_xnames[blade_class][instance],
                'blade_class': blade_class,
                'blade_instance': instance,
                'networks': {
                    discovery_net['network_name']: {
                        'mac': virtual_networks.blade_class_addressing(
                            blade_class, discovery_net['network_name']
                        ).address('AF_PACKET', instance),
                        'ipv4':  virtual_networks.blade_class_addressing(
                            blade_class, discovery_net['network_name']
                        ).address('AF_INET', instance),
                        'redfish_username':  discovery_net['redfish_username'],
                        'redfish_password':  discovery_net['redfish_password'],
                    }
                    for _, discovery_net in discovery_networks.items()
                    if virtual_networks.blade_class_addressing(
                        blade_class, discovery_net['network_name']
                    ) is not None
                }
            }
            for blade_class, count in blade_counts.items()
            for instance in range(0, count)
        }
        # Remap the blade class information into BMC network
        # information indexed by the BMC XNAME for all blades that
        # contain at least one connected network.  Pick the first
        # network. Since all are discovery networks, any one will do
        # (really there should only be one).
        return {
            bmc_info['xname']: {
                'blade_class': bmc_info['blade_class'],
                'blade_instance': bmc_info['blade_instance'],
                'network': list(bmc_info['networks'].items())[0][1],
            }
            for _, bmc_info in blade_info.items()
            if bmc_info['networks']
        }

    def __tpl_data_quadlet_nodes(self):
        """
        Template Data Collector

        Construct the 'nodes' element of the quadlet system
        template data.

        """
        cluster = self.stack.get_cluster_api()
        virtual_nodes = cluster.get_virtual_nodes()

        # We are going to go through the node classes and their
        # instances assigning NID values to each node. To make this
        # repeatable on a given config, sort the node class names so
        # they come up in the same order every time.
        managed_node_classes = self.__node_classes_by_role('managed')
        bmc_xnames = self.__bmc_xnames_by_node_class(
            managed_node_classes
        )
        bmc_instances = {
            (node_class, instance): (
                int(instance / virtual_nodes.node_host_blade_info(
                    node_class
                )['instance_capacity'])
            )
            for node_class in bmc_xnames.keys()
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
                'bmc_xname': bmc_xnames[node_class][
                    bmc_instances[(node_class, instance)]
                ],
                'cluster_net_interface': self.__cluster_network(),
                'management_net_interface': self.__management_network(),
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
            for node_class, addressing in bmc_xnames.items()
            for instance in range(0, virtual_nodes.node_count(node_class))
        ]

    def __tpl_data_quadlet_managed_macs(self):
        """
        Template Data Collector

        Get the list of MAC addresses for Manaaged Nodes on their
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

    def __find_nat_if_ip(self):
        """The "external" interface on which we apply NAT to permit
           external internet access is the same interface on which the
           blade interconnect that supports the management network is
           constructed. Obtain the IP address on that blade
           interconnect of the host blade for the management node and
           use that as the key for looking up the interface on which
           to set up NAT.

        """
        # All of the following were vetted by validate() so we can
        # simply use them...
        host_config = self.config['host']
        host_network = host_config['network']
        host_node_class = host_config['node_class']
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        virtual_networks = self.stack.get_cluster_api().get_virtual_networks()
        virtual_blades = self.stack.get_provider_api().get_virtual_blades()
        host_blade_class = (
            virtual_nodes.node_host_blade_info(host_node_class)['blade_class']
        )
        blade_interconnect = virtual_networks.blade_interconnect(host_network)
        # We are only going to do this on the first (should be only) instance
        # of the management node, which always lives on the first virtual
        # blade that hosts management nodes, so just use instance 0 here.
        return virtual_blades.blade_ip(host_blade_class, 0, blade_interconnect)

    def __tpl_data_quadlet_hosting_cfg(self):
        """
        Template Data Collector

        Get the configuration for hosting nodes under management by
        OpenCHAMI on this system. This includes the management network
        IP setup, the management node IP and FQDN within the cluster,
        whether or not libvirt hosting of a "Compute Node" on the
        Management node is to be allowed (i.e. the tutorial use case),
        and, if so, what the libvirt network setup is, and so forth.

        """
        virtual_nodes = self.stack.get_cluster_api().get_virtual_nodes()
        virtual_networks = self.stack.get_cluster_api().get_virtual_networks()
        cluster_net_name = self.__cluster_network()
        cluster_dhcp_pool = self.__cluster_net_coredhcp()['pool']
        dns = self.__dns_config()
        cluster_net_cidr = virtual_networks.ipv4_cidr(cluster_net_name)
        cluster_net_mask = str(
            ip_network(cluster_net_cidr, strict=False).netmask
        )
        return {
            'management': {
                'enable': True,
                'net_head_host': self.config['host']['node_name'],
                'net_head_domain': self.config['cluster']['domain_name'],
                'net_head_fqdn': (
                    "%s.%s" % (
                        self.config['host']['node_name'],
                        self.config['cluster']['domain_name']
                    )
                ),
                'net_head_ip': virtual_nodes.node_ipv4_addr(
                    self.config['host']['node_class'],
                    0,
                    cluster_net_name
                ),
                'cluster_net_dhcp_start': cluster_dhcp_pool['start'],
                'cluster_net_dhcp_end': cluster_dhcp_pool['end'],
                'cluster_net_cidr': cluster_net_cidr,
                'cluster_net_mask': cluster_net_mask,
                'nat_if_ip_addr': self.__find_nat_if_ip(),
                # The IP address where the head-node's FQDN and
                # external DNS are configured: normally the management
                # network address of the first Virtual Blade hosting a
                # management node.
                'net_head_dns_server': dns['site'],
                'upstream_dns_server': dns['public'],
            },
        }

    # pylint: disable=invalid-name
    def __tpl_data_quadlet_image_builders(self):
        """
        Template Data Collector

        Return a list of image builder tags that can be used to
        compose image builder file names in the order in which the
        builds are to be performed.

        """
        build_order = self.config.get('images', {}).get('build_order', [])
        image_builder_tags = list(
            self.config.get('images', {}).get('builders', {}).keys()
        )
        for builder in build_order:
            if builder not in image_builder_tags:
                raise ContextualError(
                    "image build order contains an image tag '%s' that is not "
                    "one of the supplied image builders" % builder
                )
        return build_order + [
            builder
            for builder in image_builder_tags
            if builder not in build_order
        ]

    def __tpl_data_quadlet(self):
        """
        Template Data Collector

        Construct the template data dictionary used for building
        templated deployment files for the Quadlet based mode of
        deployment.

        """
        tpl_data = self.__tpl_data()
        tpl_data['nodes'] = self.__tpl_data_quadlet_nodes()
        tpl_data['managed_macs'] = self.__tpl_data_quadlet_managed_macs()
        tpl_data['hosting_config'] = self.__tpl_data_quadlet_hosting_cfg()
        tpl_data['bmcs'] = self.__tpl_data_quadlet_bmcs()
        tpl_data['image_builders'] = self.__tpl_data_quadlet_image_builders()
        tpl_data['active_image'] = (
            self.config.get('images', {}).get('active', 'UNSPECIFIED')
        )
        return tpl_data

    def __tpl_data_bare(self):
        """Template Data Collector

        Construct the template data dictionary used for building
        templated deployment files for the Bare System mode of
        deployment.

        """
        tpl_data = self.__tpl_data()
        tpl_data['hosting_config'] = self.__tpl_data_quadlet_hosting_cfg()
        tpl_data['bmcs'] = self.__tpl_data_quadlet_bmcs()
        return tpl_data

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
                        list(self.tpl_data_calls.keys())
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
                        list(deployment_files.keys())
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

    @staticmethod
    def __generate_groupadd_cmd(group):
        """Given a 'group' description from the 'images' section,
        compute a 'groupadd' command and return it as a command
        dictionary for the builder.

        """
        name = group.get('name', None)
        if name is None:
            raise ContextualError(
                "group entry '%s' in image section is missing its 'name' "
                "setting" % (str(group))
            )
        return {'cmd': "groupadd -f %s" % name}

    @staticmethod
    def __user_password(user):
        """Produce an argument for the 'useradd' -p option, either the
        value found in the config if it is not None or missing, or a
        generated and MD5 hashed password hash if none is specified
        and return the string.

        """
        password = user.get('password', None)
        return password if password is not None else md5_crypt.hash(
            pwd.genword(length=20)
        )

    @classmethod
    def __generate_useradd_cmd(cls, user):
        """Given a 'user' description from the 'images' section,
        compute a 'useradd' command and return it as a command
        dictionary for the builder.

        """
        name = user.get('name', None)
        if name is None:
            raise ContextualError(
                "user entry '%s' in image section is missing its 'name' "
                "setting" % (str(user))
            )
        cmd = "useradd -m"
        cmd += "-G %s" % ','.join(user['supplementary_groups']) if user.get(
            'supplementary_groups', []
        ) else ""
        cmd += " -g %s" % user.get('primary_group', "")
        cmd += " -p %s" % cls.__user_password(user)
        return {"cmd": cmd}

    def __prepare_image_configs(self):
        """Go through the image builders and add commands to add users
        and groups as needed to the builders so that the builders will
        build correctly. Return an 'images' section containing the new
        content.

        """
        images = self.config['images']
        builders = images.get('builders', {})
        for name, content in builders.items():
            commands = content.get('cmds', [])
            groups = images.get('groups', {}).get(name, [])
            for group in groups:
                # Put the commands to add groups first so we can use
                # the groups in any subsequent commands
                commands.insert(0, self.__generate_groupadd_cmd(group))
            users = images.get('users', {}).get(name, [])
            for user in users:
                # Put the commands to add users next so we can use the
                # users in any subsequent commands. Any configuration
                # supplied commands will come after that.
                commands.insert(0, self.__generate_useradd_cmd(user))
            content['cmds'] = commands
        return images

    def consolidate(self):
        # Before preparing to ship files, make sure that the node
        # xnames have been installed in the cluster layer for us to
        # use.
        self.__set_node_xnames()

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
                password if password is not None else pwd.genword(length=20)
            )
        self.config['discovery_networks'] = filtered_discovery_networks
        self.config['images'] = self.__prepare_image_configs()

    def prepare(self):
        self.prepared = True

    def validate(self):
        if not self.prepared:
            raise ContextualError(
                "cannot validate an unprepared application, "
                "call prepare() first"
            )
        self.__validate_host_info()
        self.__validate_cluster_info()
        self.__validate_discovery_networks()

    def deploy(self):
        if not self.prepared:
            raise ContextualError(
                "cannot deploy an unprepared application, call prepare() first"
            )
        # Set up for preparing and shipping deployment files
        #
        # Get the deployment mode from the config. Default to 'quadlet'.
        self.deploy_mode = (
            self.config.get('deployment', {}).get('mode', 'quadlet')
        )
        self.tpl_data = self.__choose_tpl_data()
        deployed_files = self.__choose_deployment_files()

        # Deploy the application to the cluster
        blade_files, management_node_files = deployed_files
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
