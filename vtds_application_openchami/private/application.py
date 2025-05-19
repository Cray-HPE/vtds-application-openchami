#
# MIT License
#
# (C) Copyright [2024] Hewlett Packard Enterprise Development LP
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

from vtds_base import (
    info_msg,
    ContextualError,
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

    @staticmethod
    def __deploy_files(connections, files):
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
            connections.copy_to(
                source, dest,
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
                info_msg("running '%s' on host-node node(s)" % dest)
                connections.run_command(dest, "run-%s-on" % tag)

    def consolidate(self):
        return

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
