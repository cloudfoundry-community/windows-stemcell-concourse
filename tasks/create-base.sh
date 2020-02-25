#!/bin/bash

set -e
set -o errtrace

export ROOT_FOLDER
export THIS_FOLDER

ROOT_FOLDER="$(pwd)"
THIS_FOLDER="$(dirname "${BASH_SOURCE[0]}")"

#######################################
#       Validate required
#######################################
[[ -z "${vcenter_host}" ]] && (echo "vcenter_host is a required value" && exit 1)
[[ -z "${vcenter_username}" ]] && (echo "vcenter_username is a required value" && exit 1)
[[ -z "${vcenter_password}" ]] && (echo "vcenter_password is a required value" && exit 1)
[[ -z "${vcenter_datacenter}" ]] && (echo "vcenter_datacenter is a required value" && exit 1)
[[ -z "${base_vm_name}" ]] && (echo "base_vm_name is a required value" && exit 1)
[[ -z "${vm_folder}" ]] && (echo "vm_folder is a required value" && exit 1)
[[ -z "${vm_datastore}" ]] && (echo "vm_datastore is a required value" && exit 1)
[[ -z "${vm_host}" ]] && (echo "vm_host is a required value" && exit 1)
[[ -z "${esxi_version}" ]] && (echo "esxi_version is a required value" && exit 1)
[[ -z "${iso_datastore}" ]] && (echo "iso_datastore is a required value" && exit 1)
[[ -z "${iso_path_in_datastore}" ]] && (echo "iso_path_in_datastore is a required value" && exit 1)
[[ -z "${operating_system_name}" ]] && (echo "operating_system_name is a required value" && exit 1) #"Windows Server 2019 SERVERSTANDARDCORE"
[[ -z "${ip_address}" ]] && (echo "ip_address is a required value" && exit 1)
[[ -z "${gateway_address}" ]] && (echo "gateway_address is a required value" && exit 1)
[[ -z "${dns_address}" ]] && (echo "dns_address is a required value" && exit 1)
[[ -z "${admin_password}" ]] && (echo "admin_password is a required value" && exit 1)

#######################################
#       Default optional
#######################################
vcenter_ca_certs=${vcenter_ca_certs:=''}
vm_network=${vm_network:='VM Network'}
vm_cpu=${vm_cpu:=4}
vm_memory_mb=${vm_memory_mb:=8000}
vm_disk_gb=${vm_disk_gb:=100}
vm_resource_pool=${vm_resource_pool:=''}
product_key=${product_key:=''}
subnet_mask=${subnet_mask:='255.255.255.0'}
language=${language:='en-US'}
vmware_tools_uri=${vmware_tools_uri:='https://packages.vmware.com/tools/releases/10.3.10/windows/x64/VMware-tools-10.3.10-12406962-x86_64.exe'}
windows_update_module_uri=${windows_update_module_uri:='http://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc/file/41459/25/PSWindowsUpdate.zip'}
vm_guest_os_id=${vm_guest_os_id:='windows9Server64Guest'}
vm_net_adapter=${vm_net_adapter:='e1000e'}
firmware_type=${firmware_type:='bios'}
disk_controller_type=${disk_controller_type:='lsilogic-sas'}
iso_folder=${iso_folder:='Win-Stemcell-ISO'}
windows_install_timeout=${windows_install_timeout:=10m}
vmware_tools_status=${vmware_tools_status:='current'}

#######################################
#       Source helper functions
#######################################
source "${THIS_FOLDER}/functions/utility.sh"
source "${THIS_FOLDER}/functions/autounattend.sh"
source "${THIS_FOLDER}/functions/govc.sh"

if ! initializeGovc "${vcenter_host}" \
	"${vcenter_username}" \
	"${vcenter_password}" \
	"${vcenter_ca_certs}" \
	"${vcenter_datacenter}" ; then
	writeErr "error initializing govc"
	exit 1
fi

#######################################
#       Begin task
#######################################
#set -x #echo all commands

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")

autounattendPath="$(find "${ROOT_FOLDER}/autounattend" -iname "autounattend.xml" 2>/dev/null | head -n1)"
[[ ! -f "${autounattendPath}" ]] && (writeErr "autounattend.xml not found in ${ROOT_FOLDER}/autounattend" && exit 1)
unattendPath="$(find "${ROOT_FOLDER}/autounattend" -iname "unattend.xml" 2>/dev/null | head -n1)"
[[ ! -f "${unattendPath}" ]] && (writeErr "unattend.xml not found in ${ROOT_FOLDER}/unattend" && exit 1)

echo "--------------------------------------------------------"
echo "Format autounattend"
echo "--------------------------------------------------------"
cidr=$(subnetMaskToCidr "${subnet_mask}")

# format the file in place (no clone)
if ! formatAutoUnattend \
	"${autounattendPath}" \
	"${operating_system_name}" \
	"${language}" \
	"${product_key}" \
	"${ip_address}/${cidr}" \
	"${gateway_address}" \
	"${dns_address}" \
	"${vmware_tools_uri}" \
	"${windows_update_module_uri}"; then
	writeErr "formatting autounattend"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Format OOBE unattend"
echo "--------------------------------------------------------"
# format the file in place (no clone)
if ! formatUnattend \
	"${unattendPath}" \
	"${language}" \
	"${admin_password}"; then
	writeErr "formatting OOBE unattend"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Create base VM"
echo "--------------------------------------------------------"
#Remove the VM if it already exists
if ! destroyVM "${baseVMIPath}"; then
	writeErr "destroying existing VM at ${baseVMIPath}"
	exit 1
fi

if ! createVMwithISO "${base_vm_name}" \
	"${vm_datastore}" \
	"${vm_host}" \
	"${vm_network}" \
	${vm_cpu} \
	${vm_memory_mb} \
	${vm_disk_gb} \
	"${vm_folder}" \
	"${vm_guest_os_id}" \
	"${iso_datastore}" \
	"${iso_path_in_datastore}" \
	"${vm_net_adapter}" \
	"${esxi_version}" \
	"${firmware_type}" \
	"${disk_controller_type}" \
	"${vm_resource_pool}" \
	"${vcenter_datacenter}"; then
	writeErr "creating base VM"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Set boot order & connect CDRom"
echo "--------------------------------------------------------"
if ! setBootOrder "${baseVMIPath}"; then
	writeErr "setting boot order"
	exit 1
fi

if ! connectDevice "${baseVMIPath}" "cdrom-3000"; then
	writeErr "connecting device"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Create and insert floppy boot image"
echo "--------------------------------------------------------"
dd if=/dev/zero of=/tmp/boot.img count=1440 bs=1k
/sbin/mkfs.msdos /tmp/boot.img
mcopy -i /tmp/boot.img "${autounattendPath}" ::/
mcopy -i /tmp/boot.img "${unattendPath}" ::/

datastoreFolder=$(dirname "${iso_path_in_datastore}")
if ! uploadToDatastore "/tmp/boot.img" "${iso_datastore}" "${datastoreFolder}/boot.img"; then
	writeErr "uploading floppy image to datastore"
	exit 1
else
	echo "Done"
fi

if ! insertFloppy "${base_vm_name}" "${iso_datastore}" "${datastoreFolder}/boot.img"; then
	writeErr "inserting floppy image on VM"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Power on VM and begin install windows"
echo "--------------------------------------------------------"
if ! powerOnVM "${baseVMIPath}" 0 1; then
	writeErr "powering on VM"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Wait for windows install to complete"
echo "--------------------------------------------------------"

if ! powerState=$(getPowerState "${baseVMIPath}"); then
	writeErr "Could not get power state VM at path ${vm_ipath}"
	exit 1
fi

echo -ne "|"

set +e #turn "exit on error" off so we can catch the timeout

#while the VM will reboot during windows install, vsphere will not change its powerstate to poweredOff until it's actually powered off
timeout --foreground ${windows_install_timeout} bash -c 'while [[ $(getPowerState "'${baseVMIPath}'") == *"poweredOn"* ]] ; do echo -ne "."; sleep 1m; done'

if [[ $? == 124 ]]; then
	echo ""
	writeErr "Timed out waiting for windows to install"
	exit 1
fi

set -e

echo "|"

echo "Done"

echo "--------------------------------------------------------"
echo "Eject cdrom"
echo "--------------------------------------------------------"
if ! ejectCDRom "${baseVMIPath}"; then
	writeErr "ejecting cdrom"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Remove floppy drive"
echo "--------------------------------------------------------"
if ! ejectAndRemoveFloppyDrive "${baseVMIPath}"; then
	writeErr "removing floppy drive"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Validating vmware tools"
echo "--------------------------------------------------------"

if ! validateToolsVersionStatus "${baseVMIPath}" "${vmware_tools_status}"; then
	exit 1
fi

echo "Done"

#######################################
#       Return result
#######################################
exit 0
