# Windows Stemcell Automation

Provides tasks to create a Windows stemcell for Cloud Foundry, in VSphere. The tasks are intended to be open and extensible, as bash scripts. While life becomes a little more managable using [concourse](https://concourse-ci.org) for automation of these tasks, everything is arranged in a way that you could manually run them or plug them in to some other automation tool. The job of each task follows Pivotal's recommended way of creating a base image, cloning it, and running their stembuild tool on it. Read more about "Creating a Windows Stemcell for vSphere Using stembuild" in [their docs](https://docs.pivotal.io/platform/application-service-windows/2-7/create-vsphere-stemcell-automatically.html).

One notable design choice of this approach is the use of the [Windows answer file](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup) (also known as the autounattend file). An alternate option to this would be to use [packer cli](https://github.com/hashicorp/packer) made by Hashicorp. This project is focused on the Winodws operating system solely and wants to follow Microsoft's recommended approach to automating Windows installs. There are many many customizations that one could want to do to a Windows install and the autounattend approach is a guarantee to offer all possibilities.

That said, the autounattend xml is complex and confusing. So attempts are made to abstract some of that away by pulling out specific settings as pipeline variables and templatizing the XML.

![Concourse screenshot](screenshot.png "Concourse screenshot")

## A walk around the project

  ```console
  ├── assets - The needed assets for running the tasks
  │   ├── autounattend.xml - The template xml to automate windows installation
  │   └── unattend.xml - The template xml to automate windows account creation
  ├── tasks - Holds all the main scripts and helper functions
  │   ├── functions - Hold helper scripts used through out the tasks
  │   │   ├── autounattend.sh - For parsing the autounattend xml template and replacing placeholders with values supplied
  │   │   ├── govc.sh - Interpreting functions made available by the vsphere api with supplied values
  │   │   ├── .xml - Templates to be used into the templates :)
  │   │   └── utility.sh - Odd global functions for formatting and installing dependencies
  │   ├── clone-base.sh - Take the resulting VM of the `create-base` task and clone it, to be used for a specfic stembuild version
  │   ├── clone-base.yml - The concourse definition of the task
  │   ├── construct.sh - Take the resulting VM of the `clone-base` task, run stembuild to harden it for Cloud Foundry, and sysprep it
  │   ├── construct.yml - The concourse definition of the task
  │   ├── create-base.sh - The initial task to be run that takes a Windows ISO image, installs as a VM, runs Windows updates, and loads other tools
  │   ├── create-base.yml - The concourse definition of the task
  │   ├── package.sh - Take the sysprepped (shut down) VM of the `construct` task, download the image, and convert to a stemcell format
  │   ├── package.yml - The concourse definition of the task
  │   ├── update-base.sh - Power on the base VM and run windows update on it a few times, then power off
  │   └── update-base.yml - The concourse definition of the task
  ├── tests - For running the tasks locally
  │   ├── stemcell - Holds the final stemcell file
  │   ├── concourse.sh - Run the concourse tasks, without creating the pipeline using the `fly execute` command
  │   ├── functions.sh - Mimic what all the tasks do, calling the appropriate function in `/tasks/functions`
  │   ├── tasks.sh - Mimic what all the tasks do, calling the appropriate .sh script in `/tasks`
  └── pipeline.yml - The concourse pipeline definition
  └── vars-min.yml - A template for providing the minimum required values to the concourse pipeline
  ```

## Getting Started in concourse

### Setting things up

  The pipeline definition offers different ways to store the needed assets. In either S3 compatible, AWS S3, Google Cloud Store, or Azure Blob Store. An example of S3 compatible is [Minio](https://min.io) or [Dell EMC ECS Object Store](https://www.dellemc.com/en-us/storage/ecs/index.htm). Each pipeline job is run on an [Ubuntu image](https://hub.docker.com/_/ubuntu) that has the required tools already installed (curl, jq, dosfstools, mtools, xmlstarlet). There are a few assets needed to run the pipeline...

  1. A current Windows image. Testing was done with Windows Server 2019 but you could also use Server 1709 or Server 1803. Windows ISO images are not distributable, so you will need to manually add it to the vSphere datastore. Note within the store, the pipeline is expecting the ISO to be within a datastore folder named `Win-Stemcell-ISO`. For testing you can download the [trial Windows Server 2019 ISO](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019).

  1. Autounattend template xml with placeholders. During the `create-base` task the placeholders are filled with the provided pipeline values and the xml is combined with the ISO. Find this in the /assets folder. Read more about all the possabilities [in the docs](https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend). Note within the store, the pipeline is expecting the xml to be within a folder named `autounattend`.

  1. Unattend template xml with placeholders. During the install of Windows, there a different passes made. Each pass has a specific context and permission for completing the overall install. This template is used during the out of box experience (oobe) pass to create the administrator account and set its password. Find this in the /assets folder. The task will download this file when needed.

  1. Govc executable, see the [docs](https://github.com/vmware/govmomi) for more detail. The pipeleline is set to download the latest stable 0.21 release.

  1. The Local Group Policy Object(LGPO) Utility. See the [docs](https://blogs.technet.microsoft.com/secguide/2016/01/21/lgpo-exe-local-group-policy-object-utility-v1-0/) for more detail. This is a non-distributable tool, so you will need to [download LGPO.zip here](https://www.microsoft.com/en-us/download/details.aspx?id=55319) and manually add it to the blob store. Note within the store, the pipeline is expecting the zip to be within a folder named `lgpo`.

  1. Stembuild executable, see the [docs](https://github.com/cloudfoundry-incubator/stembuild) for more detail. The pipeleline is set to download the latest stable release from Pivotal, that matches the ISO operating system version (1709, 1803, 2019). There is also an option to download the same asset from the project's GitHub releases.

### Adding the pipeline

  1. You'll need 2 files from this repo, `pipeline.yml` and `vars-min.yml`. You can either clone the repo `git clone https://github.com/cloudfoundry-community/windows-stemcell-concourse` or just grab the raw content.

  1. The `vars-min.yml` file will feed values to the pipeline. This yml is a minimum to get started, read below for additional values.

  1. Using the [fly cli](https://concourse-ci.org/fly.html), [login](https://concourse-ci.org/fly.html#fly-login) to concourse, and [set](https://concourse-ci.org/setting-pipelines.html#fly-set-pipeline) the pipeline with variables filled.

#### Powershell Set Pipeline

 ```powershell
  fly -t <MY-TARGET> set-pipeline `
   --pipeline create-windows-stemcell `
   --config .\pipeline.yml `
   --load-vars-from .\vars-min.yml
 ```

#### Bash Set Pipeline

 ```bash
 fly -t <MY-TARGET> set-pipeline \
   --pipeline create-windows-stemcell \
   --config ./pipeline.yml \
   --load-vars-from ./vars-min.yml
 ```

### Building variables yaml

(Bolded example values are the defaults)

| Variable Name                   | Value                                               | Required  | Example Values         |
| ------------------------------- | --------------------------------------------------- |:---------:| ---------------------- |
| vcenter-host | The DNS or IP address to vcenter server. Do not include http(s):// | Yes | myvcenter.domain.com |
| vcenter-username | User to interact with vcenter server. Needs the permission to create/config/remove VMs. | Yes | (string) |
| vcenter-password | Password for vcenter user. | Yes | (string) |
| vcenter-datacenter | Vsphere datacenter name, for placing VMs and data. Do not include a slash(/). | Yes | (alphanumeric, underscore, dash) |
| vcenter-ca-certs | To connect with vcenter over a secure connection, you'll need to provide the certificate. Follow [this vmware doc](https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.vcli.getstart.doc%2FGUID-9AF8E0A7-1A64-4839-AB97-2F18D8ECB9FE.html) to retrieve the Base64 string. Stembuild requires secure connections, which makes this variable required. | Yes | (string) |
| base-vm-name | The name of the initial Windows VM created, used as a clone for stembuild. | Yes | **Win-Stemcell-Base** |
| vm-folder | The vsphere datacenter VM folder to hold base and clone VMs. | Yes | Stemcell |
| vm-datastore | The vsphere datastore to hold VM disks. | Yes | (alphanumeric, underscore, dash) |
| vm-resource-pool | The vsphere resource pool where VMs are created. | No |   |
| vm-network | The vsphere network name to associate with VMs | No | **VM Network** |
| vm-host | The vsphere host name or IP to create VMs on. | Yes |   |
| vm-cpu | Number of CPUs to give new VMs. Provide number only. | No | **4** |
| vm-disk-gb | Size of disk (in gb) to give new VMs. Provide number only. | No | **100** |
| vm-memory-mb | Amount of memory (in mb) to give new VMs. Provide number only | No | **8000** |
| vm-guest-os-id | Vsphere VM operating system identifier. See the [docs](https://vdc-download.vmware.com/vmwb-repository/dcr-public/da47f910-60ac-438b-8b9b-6122f4d14524/16b7274a-bf8b-4b4c-a05e-746f2aa93c8c/doc/vim.vm.GuestOsDescriptor.GuestOsIdentifier.html) for more detail. | No | **windows9Server64Guest** |
| vm-net-adapter | Type of network adaptor to attach to VMs. | No | **e1000e** |
| esxi-version | Version of esxi the `vm-host` is using. | Yes | 6.5, 6.0, ...  |
| firmware-type | Firmware type for the VMs attached disk. | No | **bios**, efi, ...  |
| disk-controller-type | Type of controller for the attached disk. | No | **lsilogic-sas**, IDE, BusLogic, ... |
| iso-datastore | The vcenter datastore name where the formatted ISO will be uploaded. !!Note the VMs need to have access to this datastore,  from their `vm-datastore` to retrieve the ISO. | Yes | (alphanumeric, underscore, dash) |
| iso-path-in-datastore | The Windows ISO file path in `iso-datastore`.  | Yes | **Win-Stemcell-ISO/windows2019.iso** |
| operating-system-name | Used during the Windows installaton. Most ISOs hold different flavors of an OS and during install you specify which is desired. See the [docs](https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-imageinstall-dataimage-installfrom-metadata) for more detail. | Yes | Windows Server 2019 SERVERSTANDARDCORE |
| ip-address | The network address assigned to the VM. Note that both the base and the clone(s) use the same IP, as they should never need to be powered on at the same time. The address needs to be routable to wherevere the tasks are run from (local desktop, concourse worker, etc). | Yes | 10.0.0.5 |
| subnet-mask | The subnet mask of the IP address of the VM. | No | **255.255.255.0** |
| gateway-address | The address of the gateway network service. | Yes | (IP, DNS name) |
| dns-address | The address of the DNS network service. | Yes | (IP, DNS name) |
| admin-password | The Windows administrator password of the base VM. Stembuild will scramble the cloned VM password. | Yes | (alphanumeric) |
| product-key | The Windows product key. | No | (alphanumeric) |
| language | The default language, locale, and other international settings to use during Windows Setup. See the [docs](https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-international-core-winpe) for more detail. | No | **en-US** |
| vmware-tools-uri | The exe to install VMWare tools. This is required by stembuild as well as a VSphere best practice. See the [FTP](https://packages.vmware.com/tools/releases/10.3.10/windows/x64) to manually download. | No | **Current tested version 10.3.10** |
| windows-update-module-uri | The powershell module used to run window update and control reboots. See the [technet script center listing](https://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc) for more detail. | No | **PSWindowsUpdate.zip** |

## Best practice for patching the base operating system

Naturally you would think patch tuesday is the trigger to update the base VM and run stembuild to create a patched stemcell. But doing this would leave compatability between OS patches and the stembuild tool up to you. The Cloud Foundry windows team does this validation for the community each month and releases a patched version of stembuild, signifying compatability with everything.

The new release of stembuild is the trigger of the pipeline. Specifically the `update-base` task. The flow should be to update the base VM's operating system, clone it with a name of the intended stembuild version, and run the latest version of stembuild on it. The output is an up to date stemcell that can trigger other pipelines for deployment and repaving of the Windows cells.

There are two ways to watch for a new stembuild release. Pivotal customers can have concourse watch [Pivotal Stemcells product page](https://network.pivotal.io/products/stemcells-windows-server) for a new version, or non-Pivotal customers can have concourse watch the [GitHub> releases](https://github.com/cloudfoundry-incubator/stembuild/releases) for a new version. If you would like to make the pipeline run automatically when a new release is posted, uncomment `trigger: true` in the `update-base` task.

More details about monthly stemcell upgrade can be found in the [creating vsphere stemcell with stembuild](https://docs.pivotal.io/pivotalcf/2-6/windows/create-vsphere-stemcell-automatically.html#upgrade-stemcell) documentation.

## Helps & Docs

There is a helper powershell file named `commands.ps1`. This has example scripts for setting up an S3 bucket in AWS (using their powershell commands), example concourse command to set the pipeline, and an example script to retrieve VCenter certificate.

## Debugging and KB

**Following Windows install progress**
When the install get started, open the VM in remote console, grab some popcorn, and watch the install go. The VM will shut down when everything is finished. Don't click or modify anything when windows popup.

**Windows install hangs**
Log in to VSphere and open the VM in the remote console. You should be greeted with a window describing why the install couldn't finish.

**I see the log message: creating filesystem that does not conform to ISO-9660**
This message is a result of how the ISO is being regenerated with the new autounattend. Windows allows things that are not always viewed as best practice when it comes to a Linux filesystem. To learn about each param being used during ISO creating read [the genisoimage manpage](https://manpages.debian.org/buster/genisoimage/genisoimage.1.en.html). Specifically look at the `-R` and `-relaxed-filenames` switches.

**What about a product license?**
Windows and product licenses are like PB&J. They always go together. There are definatly [provisions in the unattend file](https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-userdata-productkey-key) for just such a thing. This project makes the assumption that the resulting stemcell image will be deployed on Cloud Foundry for Windows, which already has the ability to provide licenses or key management servers. You can extend the provided xml template and add in things like this, as needed.

**Why is the iso file hardcoded in pipeline yaml?**
It is assumed you will have multiple iso's. So as to not get things mixed up, the pipeline has hardcoded this.

## Docker
Building a new base image for Concourse jobs or running bats tests:

```bash
$ docker build -t windows-stemcell-concourse . 
```
