# vtds-application-openchami

This vTDS Application Layer implementation configures, installs and
deploys the OpenCHAMI system management application on a vTDS Cluster
using the
[QuickStart Deployment Recipe for OpenCHAMI](https://github.com/OpenCHAMI/deployment-recipes/blob/main/quickstart/README.md).

## Description

This is an Application Layer implementation for vTDS that contains the
code and base configuration needed to deploy a simple Docker Compose
hosted OpenCHAMI control plane onto a vTDS Virtual Node using the
procedure outlined in the
[QuickStart Deployment Recipe for OpenCHAMI](https://github.com/OpenCHAMI/deployment-recipes/blob/main/quickstart/README.md).

For an overview of vTDS see the
[vTDS Core Description](https://github.com/Cray-HPE/vtds-core/blob/VSHA-652/README.md)

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
[vTDS Core Getting Started guide](https://github.com/Cray-HPE/vtds-core/blob/VSHA-652/README.md#getting-started-with-vtds)
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
guide](https://github.com/Cray-HPE/vtds-core/blob/VSHA-652/README.md#python-and-a-virtual-environment)
to activate your vTDS virtual environment. You should have already
done everything else in that section, so just activating the
environment should be sufficient.

### Validate Your Configuration

It is a good idea to validate your vTDS configuration to make sure it
is working properly before you start deploying your vTDS cluster. You
can do this using the `vtds validate` command. If that command runs
and finishes without errors, your configuration is set up
correctly. If it fails to run, go back and make sure you are still
logged into GCP, then try again.

### Debug your Configuration

If your configuration is not working correctly, you can find out what
the final configuration is by running: ``` vtds show_config >
full_config.yaml ``` and then looking at the contents of
`full_config.yaml`. Pay particular attention to the things you set in
your core configuration (the `provider.project.base_name` setting and
all of the Provider organization settings as well as the sources of
your configurations).

Once you find the problem, re-run validation. Repeat these steps until
validation passes.

### Deploy Your vTDS System

Now you are ready to deploy your OpenCHAMI on vTDS system. In the same
directory, with the virtual environment activated use
```
vtds deploy
```
This should take about 25 minutes or so to complete. It will produce
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

Third you need to log into the Virtual Node from the Virtual Blade
using SSH. Again, if you did not change the Cluster Layer
configuration, then that Virtual Node is named `management-001`:
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
