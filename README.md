# Windows Stemcell Automation

Provides tasks to create a Windows stemcell for Cloud Foundry, in VSphere. The tasks are intended to be open and extensible as bash scripts. While life becomes a little more managable using [concourse](https://concourse-ci.org) for automation of these tasks, everything is arranged in a way that you could manually run them or plug them in to some other automation tool. The job of each task follows Pivotal's recommended way of creating a base image, cloning it, and running their stembuild tool on it. Read more about "Creating a Windows Stemcell for vSphere Using stembuild" in [their docs](https://docs.pivotal.io/platform/application-service-windows/2-7/create-vsphere-stemcell-automatically.html).

One notable design choice of this approach is the use of the [Windows answer file](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup) (also known as the autounattend file). An alternate option to this would be to use [packer cli](https://github.com/hashicorp/packer) made by Hashicorp. This project is focused on the Winodws operating system solely and wants to follow Microsoft's recommended approach to automating Windows installs. There are many many customizations that one could want to do to a Windows install and the autounattend approach is a guarantee to offer all possibilities.

That said, the autounattend xml is complex and confusing. So attempts are made to abstract most of that away by pulling out specific settings as pipeline variables and templatizing the XML.

![Concourse screenshot](screenshot.png "Concourse screenshot")

## Documentation

For your reading pleasure we have moved documentation of the project to wiki. [Have a look](https://github.com/cloudfoundry-community/windows-stemcell-concourse/wiki).

## Best practice for patching the base operating system

Naturally you would think patch tuesday is the trigger to update the base VM and run stembuild to create a patched stemcell. But doing this would leave compatability between OS patches and the stembuild tool up to you. The Cloud Foundry windows team does this validation for the community each month and releases a patched version of stembuild, signifying compatability with everything.

The new release of stembuild is the trigger of the pipeline. Specifically the `update-base` task. The flow should be to update the base VM's operating system, clone it with a name of the intended stembuild version, and run the latest version of stembuild on it. The output is an up to date stemcell that can trigger other pipelines for deployment and repaving of the Windows cells.

There are two ways to watch for a new stembuild release. Pivotal customers can have concourse watch [Pivotal Stemcells product page](https://network.pivotal.io/products/stemcells-windows-server) for a new version, or non-Pivotal customers can have concourse watch the [GitHub> releases](https://github.com/cloudfoundry-incubator/stembuild/releases) for a new version. If you would like to make the pipeline run automatically when a new release is posted, uncomment `trigger: true` in the `update-base` task.

More details about monthly stemcell upgrade can be found in the [creating vsphere stemcell with stembuild](https://docs.pivotal.io/pivotalcf/2-6/windows/create-vsphere-stemcell-automatically.html#upgrade-stemcell) documentation.