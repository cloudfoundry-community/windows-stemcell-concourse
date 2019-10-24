#!/bin/bash

#
# Task Description:
#   Functions to run dotnet actions. By adding this script as a source, the required binaries
#   will automatically be installed
#
#	The targeted dotnet version can be overwritten by exporting DOTNET_VERSION
#	ie: export DOTNET_VERSION=2.x.x
#

exec 5>&1

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function powershellCmd(){
	local vm_ipath="${1}"
	local vm_username="${2}"
	local vm_password="${3}"
	local script="${4}"

  if ! pid=$(${govc} guest.start -ipath=${vm_ipath} -l=${vm_username}:${vm_password} \
    'C:\\Windows\\System32\\WindowsPowerShell\\V1.0\\powershell.exe -NoProfile -Command "'+${script}+'"'); then
		writeErr "could not run powershell command on VM at ${vm_ipath}"
		return 1
	fi

	if ! processInfo=$(${govc} guest.ps -ipath=${vm_ipath} -l=${vm_username}:${vm_password} -p=${pid} -X=true -x -json); then
		writeErr "could not get powershell process info on VM at ${vm_ipath}"
		return 1
	fi

	if ! exitCode=$(echo "${processInfo}" | jq '.info.ProcessInfo[0].ExitCode'); then
		writeErr "process info not be parsed for powershell command on VM at ${vm_ipath}"
		return 1
	fi

	echo "${exitCode}"
	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function uploadFile(){
	local vm_ipath="${1}"
	local vm_username="${2}"
	local vm_password="${3}"
	local source_file="${4}"
	local dest_file="${5}"

  if ! ${govc} guest.upload -ipath=${vm_ipath} -l=${vm_username}:${vm_password} -f=true "${source_file}" "${dest_file}"; then
		writeErr "Could not upload file to VM at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function insertFloppy(){
	local vm_name="${1}"
	local datastore_name="${2}"
	local floppy_img_ds_path="${3}"	

	if ! info=$(${govc} datastore.info -json ${datastore_name}); then
		writeErr "Could not get datastore info at ${datastore_name}"
		return 1
	fi

	if ! ${govc} device.floppy.add -vm="${vm_name}"; then
		writeErr "Could not add floppy drive to ${vm_name}"
		return 1
	fi

	if ! ${govc} device.floppy.insert -vm="${vm_name}" -ds="${datastore_name}" "${floppy_img_ds_path}"; then
		writeErr "Could not insert floppy file ${floppy_img_ds_path} into ${vm_name}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function mkdir(){
	local vm_ipath="${1}"
	local vm_username="${2}"
	local vm_password="${3}"
	local folder_Path="${4}"

  if ! ${govc} guest.mkdir -ipath=${vm_ipath} -l=${vm_username}:${vm_password} "${folder_Path}"; then
		writeErr "Could not make dir on VM at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function clonevm(){
	local vm_name="${1}"
	local vm_datastore="${2}"
	local vm_folder=${3}
	local vm_host="${4}"
	local vm_resource_pool="${5}"
	local vm_network="${6}"
	local vm_cpu="${7}"
	local vm_memory_mb="${8}"
	local clone_vm_name="${9}"

	#if ! folderIPath=$(buildIpath "${vm_datacenter}" "${vm_folder}"); then echo ${folderIPath}; return 1; fi
	#if ! folderExists=$(folderExists "${folderIPath}"); then echo ${folderExists}; return 1; fi

	#if [[ ${folderExists} == "false" ]]; then
	#	if ! createFolder "${folderIPath}"; then return 1; fi
	#fi

	args="-m=${vm_memory_mb} -c=${vm_cpu} -on=false -force=true -annotation='Windows cloned VM.' -ds='${vm_datastore}' -folder='${vm_folder}' -host='${vm_host}' -net='${vm_network}' -vm='${clone_vm_name}'"

	[[ ! -z ${vm_resource_pool} ]] && args="${args} -pool='${vm_resource_pool}'"

	cmd="${govc} vm.clone ${args} ${vm_name}" #finally add the VM name

	echo ${cmd} #for reference
	if ! eval "${cmd}"; then
		writeErr "Could not clone VM ${clone_vm_name} as ${vm_name}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function resizeDisk(){
	local vm_ipath="${1}"
	local disk_size_gb="${2}"

	if ! ${govc} vm.disk.change -vm.ipath=${vm_ipath} -size=${disk_size_gb}; then
		writeErr "Could not resize VM disk at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function getInfo(){
	local vm_ipath="${1}"

	if ! info=$(${govc} vm.info -json -vm.ipath="${vm_ipath}"); then
		writeErr "Could not get vm info at ${vm_ipath}"
		return 1
	fi

	echo "${info}"
	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function getPowerState(){
	local vm_ipath="${1}"

	if ! info=$(getInfo "${vm_ipath}"); then echo "${info}"; return 1; fi # 2>&1

	if ! powerState=$(echo ${info} | jq '.VirtualMachines[0].Runtime.PowerState'); then
		writeErr "Could not parse vm info at ${vm_ipath}"
		return 1
	elif [[ -z "${powerState}" ]]; then
		writeErr "Power state could not be parsed for VM at ${vm_ipath}"
		return 1
	fi

	echo "${powerState}"
	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function powerOnVM(){
	local vm_ipath="${1}"

	if ! ret=$(${govc} vm.power -vm.ipath=${vm_ipath} -on=true -wait=true 2>&1); then
		if [[ "${ret}" == *"current state (Powered on)"* ]]; then
			return 0
		else
			writeErr "${info}"
			writeErr "Could not power on VM at ${vm_ipath}"
			return 1
		fi
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function restartVM(){
	local vm_ipath="${1}"

	if ! ${govc} vm.power -vm.ipath=${vm_ipath} -r=true -wait=true; then
		writeErr "Could not restart VM at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function connectDevice(){
	local vm_ipath="${1}"
	local device_name="${2}"

	if ! ${govc} device.connect -vm.ipath=${vm_ipath} ${device_name}; then
		writeErr "Could not connect device to VM at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function powerOffVM(){
	local vm_ipath="${1}"

	if ! ${govc} vm.power -vm.ipath=${vm_ipath} -off=true -wait=true; then
		writeErr "Could not power off VM at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function buildIpath(){
	local vm_datacenter="${1}"
	local vm_folder=${2}
	local vm_name="${3}"

	if [[ -z ${vm_folder} ]]; then
		if [[ -z ${vm_name} ]]; then
			writeErr "VM name required if no folder name is provided"
			return 1
		fi

		echo "/${vm_datacenter}/vm/${vm_name}"
	else
		if [[ -z ${vm_name} ]]; then
			echo "/${vm_datacenter}/vm/${vm_folder}"
		else
			echo "/${vm_datacenter}/vm/${vm_folder}/${vm_name}"
		fi
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function vmExists(){
	local vm_ipath="${1}"
	
	if ! info=$(${govc} vm.info -json -vm.ipath="${vm_ipath}" 2>&1); then
		if [[ "${info}" == *"no such VM"* ]]; then
			echo false
			return 0
		else
			writeErr "${info}"
			return 1
		fi
	fi

	echo true
	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function validateAndPowerOn(){
	local vm_ipath="${1}"
	
	if ! powerState=$(getPowerState ${vm_ipath}); then echo "${powerState}"; return 1; fi

	if [[ "${powerState}" == *"poweredOff"* ]]; then
		if ! powerOnVM ${vm_ipath}; then return 1; fi
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function validateAndPowerOff(){
	local vm_ipath="${1}"

	if ! powerState=$(getPowerState ${vm_ipath}); then echo "${powerState}"; return 1; fi

	if [[ "${powerState}" == *"poweredOn"* ]]; then
		if ! powerOffVM ${vm_ipath}; then return 1; fi
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function uploadToDatastore(){
	local file_path="${1}"
	local datastore_name="${2}"
	local saveas_file_path="${3}"	

	if ! info=$(${govc} datastore.info -json ${datastore_name}); then
		writeErr "Could not get datastore info at ${datastore_name}"
		return 1
	fi

	if ! ${govc} datastore.upload -ds=${datastore_name} ${file_path} ${saveas_file_path}; then
		writeErr "Could not upload file as ${saveas_file_path} to datastore ${datastore_name}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	Gracefully try to remove the VM. If it doesn't exist continue on, if it does check for errors.
# Arguments:
#		
#######################################
function destroyVM(){
	local vm_ipath="${1}"

	if ! ret=$(${govc} vm.destroy -vm.ipath=${vm_ipath} 2>&1); then
		if [[ "${ret}" == *"no such VM"* ]]; then
			return 0
		else
			writeErr "${info}"
			writeErr "Could not destroy VM at ${vm_ipath}"
			return 1
		fi
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function folderExists(){
	local folder_ipath="${1}"

	if ! info=$(${govc} folder.info -json "${folder_ipath}" 2>&1); then
		if [[ "${info}" == *"not found"* ]]; then
			echo false
			return 0
		else
			writeErr "${info}"
			return 1
		fi
	fi

	echo true
	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function createFolder(){
	local folder_ipath="${1}"

	if ! ${govc} folder.create "${folder_ipath}"; then
		writeErr "Could not create folder at ${folder_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function createVMwithISO(){
	local vm_name="${1}"
	local vm_datastore="${2}"
	local vm_host="${3}"
	local vm_network="${4}"
	local vm_cpu="${5}"
	local vm_memory_mb="${6}"
	local vm_disk_gb="${7}"
	local vm_folder="${8}"
	local vm_guest_os_id="${9}"
	local iso_datastore="${10}"
	local iso_path_in_datastore="${11}"
	local vm_net_adapter="${12}"
	local esxi_version="${13}"
	local firmware_type="${14}"
	local disk_controller_type="${15}"
	local vm_resource_pool="${16}"
	local vm_datacenter="${17}"

	if ! folderIPath=$(buildIpath "${vm_datacenter}" "${vm_folder}"); then echo ${folderIPath}; return 1; fi
	if ! folderExists=$(folderExists "${folderIPath}"); then echo ${folderExists}; return 1; fi

	if [[ ${folderExists} == "false" ]]; then
		if ! createFolder "${folderIPath}"; then return 1; fi
	fi

	args="-m=${vm_memory_mb} -c=${vm_cpu} -g='${vm_guest_os_id}' -link=false -on=false -force=false -annotation='Windows base VM for Pivotal products running .NET workloads.' -disk.controller='${disk_controller_type}' -firmware='${firmware_type}' -version='${esxi_version}' -net.adapter='${vm_net_adapter}' -disk='${vm_disk_gb}gb' -iso='${iso_path_in_datastore}' -iso-datastore='${iso_datastore}' -ds='${vm_datastore}' -folder='${vm_folder}' -host='${vm_host}' -net='${vm_network}'"

	[[ ! -z ${vm_resource_pool} ]] && args="${args} -pool='${vm_resource_pool}'"
	#[[ ! -z ${vm_cluster} ]] && args="${args} -datastore-cluster='${vm_cluster}'"

	cmd="${govc} vm.create ${args} ${vm_name}" #finally add the VM name

	echo ${cmd} #for reference
	if ! eval ${cmd}; then
		writeErr "Could not create VM ${vm_name}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function setBootOrder(){
	local vm_ipath="${1}"

	if ! ${govc} device.boot -order=cdrom,disk -vm.ipath=${vm_ipath}; then
		writeErr "Could not set boot order at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		
#######################################
function ejectCDRom(){
	local vm_ipath="${1}"

	if ! ${govc} device.cdrom.eject -vm.ipath=${vm_ipath}; then
		writeErr "Could not eject CD at ${vm_ipath}"
		return 1
	fi

	return 0
}

######################################

vcenter_url=""
vcenter_username=""
vcenter_password=""
govc=""
cert_path=""
use_cert=""

echo "Initializing govc"

while [ $# -ne 0 ]
do
	name="$1"
	case "$name" in
		-govc)
				shift
				govc="$1"
				;;
    --url|-[Uu]rl)
				shift
				vcenter_url="$1"
				;;
		--username|-[Uu]sername)
				shift
				vcenter_username="$1"
				;;
		--password|-[Pp]assword)
				shift
				vcenter_password="$1"
				;;
		-[Cc]ert-path)
				shift
				cert_path="$1"
				;;
		-[Uu]se-cert)
				shift
				use_cert="$1"
				;;
	esac

	shift
done

if [ -z ${govc} ]; then
	writeErr "govc binary not found"
	exit 1
fi

if ! command -v ${govc} >/dev/nulll; then
	writeErr "govc binary invalid"
	exit 1
fi

export GOVC_URL=${vcenter_url}
export GOVC_USERNAME=${vcenter_username}
export GOVC_PASSWORD=${vcenter_password}

if [[ "${use_cert}" == "true" ]]; then
	export GOVC_INSECURE=0
	export GOVC_TLS_CA_CERTS=${cert_path}
else
	export GOVC_INSECURE=1
fi

#test that we have a good connection
if ! ret=$(${govc} about); then
	writeErr "could not connect to vcenter with provided info () - ${ret}"

	exit 1
fi

if [[ ${ret} == *"specify an"* ]]; then
	writeErr "${ret}"
	exit 1
fi
