# vtds-application-openchami

This vTDS Application Layer implementation configures, installs and
deploys the OpenCHAMI system management application on a vTDS Cluster
using procedures derived from the
[2025 OpenCHAMI Tutorial](https://github.com/OpenCHAMI/tutorial-2025).

## Description

This is an Application Layer implementation for vTDS that contains the
code and base configuration needed to deploy a Quadlet based
deployment of the OpenCHAMI control plane onto a mmanagement node and
set of managed (compute) nodes onto vTDS Virtual Blades, using vTDS
Virtual Nodes and a procedure derived from the [2025 OpenCHAMI
Tutorial](https://github.com/OpenCHAMI/tutorial-2025), or,
alternatively, to deploy a bare management node that has been prepared
to allow users to follow the 2025 OpenCHAMI Tutorial manually. This
latter system also has compute nodes defined, but they are not started
upon deployment.

For an overview of vTDS see the
[vTDS Core Description](https://github.com/Cray-HPE/vtds-core/blob/main/README.md)

## Getting Started with OpenCHAMI On vTDS

The current implementation of OpenCHAMI on vTDS uses a
[GCP Provider Layer](https://github.com/Cray-HPE/vtds-provider-gcp/blob/main/README.md)
as its foundation. When other Provider layers become available, they
will contain similar Getting Started information and that will be
linked here.

The rest of the guide here assumes you are using the
[standard configuration of OpenCHAMI on vTDS](https://github.com/Cray-HPE/vtds-configs/blob/main/core-configs/vtds-openChami-gcp.yaml)
which uses the
[GCP Provider Layer implementation](https://github.com/Cray-HPE/vtds-provider-gcp/blob/main/README.md),
an
[Ubuntu Virtual Blade based Platform Layer implementation](https://github.com/Cray-HPE/vtds-platform-ubuntu/blob/main/README.md),
a
[KVM Based Cluster Layer implementaion](https://github.com/Cray-HPE/vtds-cluster-kvm/blob/main/README.md)
, and this OpenCHAMI Application Layer implementation.

### Prepare Your System to Run vTDS Commands

Follow the instructions in the
[vTDS Core Getting Started guide](https://github.com/Cray-HPE/vtds-core/blob/main/README.md#getting-started-with-vtds)
to install the required software and create a Python virtual
environment to work in.

### Set up GCP Layer Implementation Prerequisites and Configs

Most of the work involved in getting started with OpenCHAMI on vTDS
has to do with setting up a GCP Organization and associated resources,
principals and roles. That work is described in the
[GCP Provider Layer Implementation Getting Started guide](https://github.com/Cray-HPE/vtds-provider-gcp/blob/main/README.md#getting-started-with-the-gcp-provider-implementation).
Start there to make sure you have all those pieces set up. With the
exception of logging into GCP to make sure the vTDS tools will have
access to GCP, which is covered here too, all of the activities for
the GCP Provider Layer are one time activities undertaken by either
you or an administrator.

### Create a vTDS System Directory and Core Configuration

The vTDS tool is easiest to use when you start in a directory that
contains a core configuration file named `config.yaml`. This allow you
to use simple commands with no command line options to build your
OpenCHAMI cluster. These instructions assume you are following that
approach. For this we are going to use the canned
[standard configuration of OpenCHAMI on vTDS](https://github.com/Cray-HPE/vtds-configs/blob/main/core-configs/vtds-openChami-gcp.yaml)
as a base and modify it to meet your specific needs.

#### Make the Directory and Initial Core Config

The first thing you need to do is make an empty directory somewhere
(for the example I am going to use `~/openchami`) and put the canned
core configuration into the directory as `config.yaml`:

```
mkdir ~/openchami
cd ~/openchami
curl -s https://raw.githubusercontent.com/Cray-HPE/vtds-configs/refs/heads/main/core-configs/vtds-openChami-gcp.yaml > config.yaml
```

#### Switch to Using Your GCP Organization Configuration Overlay

Next, edit your core configuration with your favorite editor, and change
the following:

```
  configurations:
  - type: git
    metadata:
      # This brings in your organization specific settings needed to
      # build a project on GCP.
      repo: git@github.com:Cray-HPE/vtds-configs.git
      version: main
      path: layers/provider/gcp/provider-gcp-example-org.yaml
```
To bring in your own GCP organization configuration. For example, if
you are hosting your organization configuration on GitHub under a repo
called `mycompany/OpenCHAMI-on-vTDS.git` in a configuration file
called `provider-gcp-organization.yaml` you would have something like
this:

```
  configurations:
  - type: git
    metadata:
      # This brings in your organization specific settings needed to
      # build a project on GCP.
      repo: git@github.com:mycompany/OpenCHAMI-onvTDS.git
      version: main
      path: provider-gcp-organization.yaml
```

#### Set the Name of your vTDS System

The last core configuration step that you need to do is to change the
name your vTDS cluster will be given when it is created to something
unique to you. For example, you might want to name it using your name
as part of the name. Names for vTDS clusters on the GCP provider are
reqtricted to lowercase letters, numerals, and dashes
('-') and are limited to 25 characters, including an organization name
prefix that will be added by vTDS. Make sure your name fits in that
space.

Change this part of the core configuration to reflect the name you
have chosen:
```
provider:
  project:
    base_name: openchami
```
For example:
```
provider:
  project:
    base_name: openchami-tilly
```
### Log Into GCP

Before you start, make sure you are fully logged into GCP:
```
gcloud auth login
```
and
```
gcloud auth application-default login
```

Both of these are needed to permit the vTDS tools to use both the GCP
client libraries and the Google Cloud SDK (`gcloud` command) on your
behalf.

### Make Sure You Activate Your Python Virtual Environment

Follow the instructions in the [vTDS Core Getting Started
guide](https://github.com/Cray-HPE/vtds-core/blob/main/README.md#python-and-a-virtual-environment)
to activate your vTDS virtual environment. You should have already
done everything else in that section, so just activating the
environment should be sufficient.

### Validate Your Configuration

It is a good idea to validate your vTDS configuration to make sure it
is working properly before you start deploying your vTDS cluster. You
can do this using the `vtds validate` command. If that command runs
and finishes without errors, your configuration is generally set up
correctly. If it fails to run, go back and make sure you are still
logged into GCP, then try again.

### Debug your Configuration

If your configuration is not working correctly, you can find out what
the final configuration is by running:

```vtds show_config > full_config.yaml```

and then looking at the contents of`full_config.yaml`. Pay particular
attention to the things you set in your core configuration (the
`provider.project.base_name` setting and all of the Provider
organization settings as well as the sources of your configurations).

Once you find the problem, re-run validation. Repeat these steps until
validation passes.

### Deploy Your vTDS System

Now you are ready to deploy your OpenCHAMI on vTDS system. In the same
directory, with the virtual environment activated use

```
vtds deploy
```

This should take about 40 minutes or so to complete. It will produce
some output, including some INFO messages that might look
surprising. If it ends without producing an ERROR message, your
OpenCHAMI on vTDS system is deployed and ready for use.

### Log Into Your Virtual Node

Logging into your virtual node is a three step process. First you need to find out the name of your vTDS system. You can do this with the following command:

```
gcloud projects list | grep <your-system basename>
```

So, for example, if your base name was `openchami-tilly`:

```
$ gcloud projects list | grep openchami-tilly
hpe-openchami-tilly-3724     hpe-openchami-tilly         414054220815
```

Second, you need to log into the virtual blade where the node
resides. If you did not change the Provider Layer configuration, that
Virtual Blade will be a GCP instance and it will be called
`host-blade-001`:

```
gcloud compute --project hpe-openchami-tilly-3724 ssh --tunnel-throug-iap root@host-blade-001 
```

Third you need to log into the management Virtual Node from the
Virtual Blade using SSH. Again, if you did not change the Cluster
Layer configuration, then that Virtual Node is named `management-001`:

```
ssh management-001
```

You are now on the your OpenCHAMI node with OpenCHAMI running locally.

### Remove Your vTDS Cluster

To remove your vTDS cluster, make sure you are logged into GCP (above)
and make sure you have your virtual environment activated
(above). Also make sure you are in the directory for your vTDS cluster
(in the example `~/openchami`). Then you can run the `vtds remove`
command and it will release all of the resources assigned to your vTDS
system.

### Changing the Standard Configuration

By overriding certain standard settings using the Core Configuration
file, you can change certain parameters of your OpenCHAMI system. This
section outlines some settings you might want to make on your system.

#### Adding Compute Virtual Nodes

By default, OpenCHAMI on vTDS has no actual compute nodes.  OpenCHAMI
on vTDS supports "real" compute nodes implemented as vTDS Virtual
Nodes and managed by their own RedFish server(s) that run on the
respective vTDS Virtual Blade(s). Up to 4 compute Virtual Nodes are
available simply by editing this section of the standard Core
Configuration file:

```
cluster:
  node_classes:
    management_node:
      # A node count of 1 creates a single management node.
      node_count: 1
    compute_node:
      # A node count of 0 prevents compute nodes from being
      # created. This is the simplest version of OpenCHAMI and will use
      # the RIE RedFish emulator to simulate the existence of compute
      # nodes. This can be increased to four for every virtual blade in
      # the cluster.
      node_count: 0
```

and setting the value of `node_count` under `compute_node` to a value
1 through 4. All of these compute nodes will run on the same virtual
blade as the management node (where your OpenCHAMI software is
running).

A Virtual Blade in the standard configuration of OpenCHAMI on vTDS
supports up to 4 compute nodes and up to 1 management node. If you
want more than 4 compute nodes, you will need to increase the number
of Virtual Blades in your system by 1 for every 4 additional compute
nodes you need (up to 4 virtual blades and 16 virtual nodes). You can
do this by adjusting this section of the Core Configuration file:

```
  virtual_blades:
    host-blade:
      # A count of 1 is sufficient to build a system on a single blade
      # with 1 management node (ochami-001) and up to four compute nodes
      # (compute-001, compute-002, compute-003, compute-004).
      #
      # For more compute nodes, increase the number of blades by one for
      # every four additional compute nodes. For additional management
      # nodes, increase the number of blades by one for every management
      # node (each blade has room for one management node and up to 4
      # compute nodes).
      count: 1
```

and setting the `host-blade` Virtual Blade count to the number of
blades required to support your additional compute nodes. For example,
if you wanted 12 compute nodes, you would need 3 `host-blade` Virtual
Blades:

```
  virtual_blades:
    host-blade:
      # A count of 1 is sufficient to build a system on a single blade
      # with 1 management node (ochami-001) and up to four compute nodes
      # (compute-001, compute-002, compute-003, compute-004).
      #
      # For more compute nodes, increase the number of blades by one for
      # every four additional compute nodes. For additional management
      # nodes, increase the number of blades by one for every management
      # node (each blade has room for one management node and up to 4
      # compute nodes).
      count: 3
```

### Basic Interaction with OpenCHAMI on vTDS

#### The `rocky` User

There is a user named `rocky` configured on the OpenCHAMI management
node. To become `rocky` first log in as `root` on the management node
as described [above](#log-into-your-virtual-node). Next use `su -
rocky` to become `rocky`. This user is the user that is set up to
interact with OpenCHAMI through the `ochami` CLI and to manage S3 and
registry storage.

To obtain an auth token for use with `ochami` use the built-in
`get-ochami-token` shell function that vTDS provides.

#### Compute Node Host Names

Your compute nodes will have both XNAMEs and NID names in the following pattern:

| XNAME | NID Name |
|---|---|
| x2000c0s0b0n0 | nid-001 |
| x2000c0s0b0n1 | nid-002 |
| x2000c0s0b0n2 | nid-003 |
| x2000c0s0b0n3 | nid-004 |
| x2000c0s0b1n0 | nid-005 |
| x2000c0s0b1n1 | nid-006 |
| x2000c0s0b1n2 | nid-007 |
| x2000c0s0b1n3 | nid-008 |
| x2000c0s0b2n0 | nid-009 |
| x2000c0s0b2n1 | nid-010 |
| x2000c0s0b2n2 | nid-011 |
| x2000c0s0b2n3 | nid-012 |
| x2000c0s0b3n0 | nid-013 |
| x2000c0s0b3n1 | nid-014 |
| x2000c0s0b3n2 | nid-015 |
| x2000c0s0b3n3 | nid-016 |

You can reach them as the `rocky` user on the management node using
SSH to either the `root` user or the `testuser` user. For example,

```
$ ssh root@nid-001
```

or
```
$ ssh root@x2000c0s0b0n0
```

will log you in as the `root` user on the first compute node.

#### Redfish Hostnames

OpenCHAMI on vTDS provides RedFish control of managed nodes via a
RedFish server running on the Virtual Blades. The virtual blades are
named using their XNAMEs and host the following managed nodes:

| Virtual Blade XNAME | Managed Nodes |
|---|---|
| x0c0s0b0 | nid-001 through nid-004 |
| x0c0s0b1 | nid-005 through nid-008 |
| x0c0s0b2 | nid-009 through nid-012 |
| x0c0s0b3 | nid-0013 through nid-016 |

When logged into the management node as the `rocky` user you can use
some built-in shell functions to manipulate the nodes via RedFish curl
commands:

- `restart-node <node-XNAME> <blade-XNAME>` uses the RedFish
  `ForceRestart` operation to reset a managed node.

- `power-on-node <node-XNAME> <blade-XNAME>` uses the RedFish `On`
  operation to power on a managed node.

- `power-off-node <node-XNAME> <blade-XNAME>` uses the RedFish `ForceOff`
  operation to power off a managed node.

For example:

```
$ restart-node x2000c0s0b0n0 x2000c0s0b0
```

will restart `nid-001`.

#### Console Access to Managed Nodes

If you want to watch your nodes boot, you will need to get onto the
console of your nodes. This is currently available using the `virsh
console` command and the XNAME of the managed node you want to connect
to while running on the Virtual Blade. Log into the virtual blade (not
the management node) hosting the managed node as shown
[above](#log-into-your-virtual-node) and run the `virsh console`
command. For example:

```
# virsh console x2000c0s0b0n0
```

will get you onto the console of `nid-001`. Be aware that resetting
the node will drop you off of the console and that the console is only
available when the node is powered on. The `virsh console` command
will issue an error indicating that the console is unavailable if the
node is powered off or in the process of resetting.

For your reference, assuming you don't change the instance names in
the configuration, the GCP instance names map to Virtual Blade XNAMEs
as follows:

| Instance Name | Blade XNAME |
|---|---|
| host-blade-001| x2000c0s0b0 |
| host-blade-002| x2000c0s0b1 |
| host-blade-003| x2000c0s0b2 |
| host-blade-004| x2000c0s0b3 |
