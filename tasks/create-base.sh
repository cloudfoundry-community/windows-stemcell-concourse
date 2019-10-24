#!/bin/bash

set -e
set -o errtrace

export ROOT_FOLDER
export THIS_FOLDER

ROOT_FOLDER="$( pwd )"
THIS_FOLDER="$( dirname "${BASH_SOURCE[0]}" )"

#######################################
#       Validate required globals
#######################################
[[ -z "${vcenter_url}" ]] && (echo "vcenter_url is a required value" && exit 1)
[[ -z "${vcenter_username}" ]] && (echo "vcenter_username is a required value" && exit 1)
[[ -z "${vcenter_password}" ]] && (echo "vcenter_password is a required value" && exit 1)
[[ -z "${vcenter_datacenter}" ]] && (echo "vcenter_datacenter is a required value" && exit 1)
[[ -z "${vcenter_ca_certs}" ]] && vcenter_ca_certs=""

[[ -z "${base_vm_name}" ]] && (echo "base_vm_name is a required value" && exit 1)

[[ -z "${vm_folder}" ]] && (echo "vm_folder is a required value" && exit 1)
[[ -z "${vm_datastore}" ]] && (echo "vm_datastore is a required value" && exit 1)
[[ -z "${vm_host}" ]] && (echo "vm_host is a required value" && exit 1)
[[ -z "${vm_network}" ]] && vm_network="VM Network"
[[ -z "${vm_cpu}" ]] && vm_cpu=4
[[ -z "${vm_memory_mb}" ]] && vm_memory_mb=8000
[[ -z "${vm_disk_gb}" ]] && vm_disk_gb=100
[[ -z "${vm_guest_os_id}" ]] && vm_guest_os_id="windows9Server64Guest"
[[ -z "${vm_net_adapter}" ]] && vm_net_adapter="e1000e"
[[ -z "${esxi_version}" ]] && (echo "esxi_version is a required value" && exit 1)
[[ -z "${firmware_type}" ]] && firmware_type="bios"
[[ -z "${disk_controller_type}" ]] && disk_controller_type="lsilogic-sas"
[[ -z "${iso_datastore}" ]] && (echo "iso_datastore is a required value" && exit 1)
[[ -z "${iso_folder}" ]] && iso_folder="Win-Stemcell-ISO"
[[ -z "${vm_resource_pool}" ]] && vm_resource_pool=""

[[ -z "${operating_system_name}" ]] && (echo "operating_system_name is a required value" && exit 1) #"Windows Server 2019 SERVERSTANDARDCORE"
[[ -z "${product_key}" ]] && product_key=""
[[ -z "${language}" ]] && language="en-US"
[[ -z "${ip_address}" ]] && (echo "ip_address is a required value" && exit 1)
[[ -z "${gateway_address}" ]] && (echo "gateway_address is a required value" && exit 1)
[[ -z "${dns_address}" ]] && (echo "dns_address is a required value" && exit 1)
[[ -z "${admin_password}" ]] && (echo "admin_password is a required value" && exit 1)

[[ -z "${oobe_unattend_uri}" ]] && oobe_unattend_uri="https://raw.githubusercontent.com/cloudfoundry-community/windows-stemcell-concourse/master/assets/unattend.xml"
[[ -z "${vmware_tools_uri}" ]] && vmware_tools_uri="https://packages.vmware.com/tools/releases/10.3.10/windows/x64/VMware-tools-10.3.10-12406962-x86_64.exe"
[[ -z "${windows_update_module_uri}" ]] && windows_update_module_uri="http://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc/file/41459/25/PSWindowsUpdate.zip"

#TESTING/MANUAL VARS
[[ -z "${use_cert}" ]] && use_cert="false" #for testing
[[ -z "${cert_path}" ]] && cert_path="" #for testing

if [[ ! -z "${vcenter_ca_certs}" ]]; then
	use_cert="true"

	#write the cert to file locally
	(echo ${vcenter_ca_certs} | awk '
		match($0,/- .* -/){
			val=substr($0,RSTART,RLENGTH)
			gsub(/- | -/,"",val)
			gsub(OFS,ORS,val)
			print substr($0,1,RSTART) ORS val ORS substr($0,RSTART+RLENGTH-1)}') > ${ROOT_FOLDER}/cert.crt
	
	cert_path=${ROOT_FOLDER}/cert.crt
fi

#######################################
#       Source helper functions
#######################################
# shellcheck source=./functions/utility.sh
source "${THIS_FOLDER}/functions/utility.sh"
# shellcheck source=./functions/autounattend.sh
source "${THIS_FOLDER}/functions/autounattend.sh"

if ! findFileExpandArchive "${ROOT_FOLDER}/govc/govc_linux_amd64" "${ROOT_FOLDER}/govc/govc_linux_amd64.gz" true; then exit 1; fi
# shellcheck source=./functions/govc.sh
source "${THIS_FOLDER}/functions/govc.sh" \
  -govc "${ROOT_FOLDER}/govc/govc_linux_amd64" \
  -url "${vcenter_url}" \
  -username "${vcenter_username}" \
  -password "${vcenter_password}" \
	-use-cert "${use_cert}" \
	-cert-path "${cert_path}" || (writeErr "error initializing govc" && exit 1)

#######################################
#       Begin task
#######################################
#set -x #echo all commands

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")

autounattendPath="$(find "${ROOT_FOLDER}/autounattend" -iname "autounattend.xml" 2>/dev/null | head -n1)"
[[ ! -f "${autounattendPath}" ]] && (writeErr "autounattend.xml not found in ${ROOT_FOLDER}/autounattend" && exit 1)

isoPath="$(find "${ROOT_FOLDER}/iso" -iname *.iso 2>/dev/null | head -n1)"
[[ ! -f "${isoPath}" ]] && (writeErr "*.iso not found in ${ROOT_FOLDER}/iso" && exit 1)

echo "--------------------------------------------------------"
echo "Format autounattend"
echo "--------------------------------------------------------"
# format the file in place (no clone)
if ! formatAutoUnattend \
			"${autounattendPath}" \
			"${operating_system_name}" \
			"${language}" \
			"${product_key}" \
			"${ip_address}" \
			"${gateway_address}" \
			"${dns_address}" \
			"${admin_password}" \
			"${oobe_unattend_uri}" \
			"${vmware_tools_uri}" \
			"${windows_update_module_uri}"; then
	writeErr "formatting autounattend" 
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Build ISO"
echo "--------------------------------------------------------"
extractISOPath="/mnt/formatIso"
finalIsoFolder="/tmp"
finalFileName="final-iso.iso"

apt-get update && apt-get -y install genisoimage
mkisofs -version
if ! 7z x -y -o${extractISOPath} "${isoPath}"; then
  writeErr "expanding iso"
  exit 1
fi

cp "${autounattendPath}" "${extractISOPath}/autounattend.xml"
finalIsoFilePath="${finalIsoFolder}/${finalFileName}"

if ! mkisofs -quiet \
  -b boot/etfsboot.com \
  -no-emul-boot \
  -boot-load-seg 0x07C0 \
  -boot-load-size 8 \
  -udf \
  -input-charset UTF-8 \
  -D -N -R -joliet -relaxed-filenames \
  -V Windows \
  -o ${finalIsoFilePath} \
	${extractISOPath}; then
  writeErr "creating new ISO"
  exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Upload ISO"
echo "--------------------------------------------------------"
if ! uploadToDatastore "${finalIsoFilePath}" "${iso_datastore}" "${iso_folder}/${base_vm_name}.iso"; then
  writeErr "uploading iso to datastore"
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
	"${iso_folder}/${base_vm_name}.iso" \
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
echo "Power on VM and begin install windows"
echo "--------------------------------------------------------"
if ! powerOnVM "${baseVMIPath}"; then
  writeErr "powering on VM"
  exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Wait for windows install to complete"
echo "--------------------------------------------------------"

echo -ne "|"
while [[ $(getPowerState "${baseVMIPath}") == *"poweredOn"* ]]; do
	echo -ne "."
  sleep 2m
	#TODO: add timeout so job doesn't run endlessly#
done

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

#######################################
#       Return result
#######################################
exit 0