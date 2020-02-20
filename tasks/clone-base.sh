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

#######################################
#       Default optional
#######################################
vcenter_ca_certs=${vcenter_ca_certs:=''}
vm_network=${vm_network:='VM Network'}
vm_cpu=${vm_cpu:=4}
vm_memory_mb=${vm_memory_mb:=8000}
vm_resource_pool=${vm_resource_pool:=''}
timeout=${timeout:=30s}

#######################################
#       Source helper functions
#######################################
source "${THIS_FOLDER}/functions/utility.sh"
source "${THIS_FOLDER}/functions/govc.sh"

if ! initializeGovc "${vcenter_host}" \
	"${vcenter_username}" \
	"${vcenter_password}" \
	"${vcenter_ca_certs}" ; then
	writeErr "error initializing govc"
	exit 1
fi

#######################################
#       Begin task
#######################################

stembuildPath="$(find "${ROOT_FOLDER}/stembuild" -iname stembuild-linux-* 2>/dev/null | head -n1)"
[[ ! -f "${stembuildPath}" ]] && (writeErr "stembuild-linux-* not found in ${stembuildPath}" && exit 1)

chmod +x "${stembuildPath}"

if [[ -z "${stembuild_vm_name}" ]]; then
	vers=$(${stembuildPath} -v)
	if ! stembuild_vm_name=$(parseStembuildVersion "${vers}"); then
		writeErr "Trying to parse stembuild version"
		exit 1
	fi
fi

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")
if ! exists=$(vmExists "${baseVMIPath}"); then
	writeErr "Error finding base VM at path ${baseVMIPath}"
	exit 1
fi

[[ ${exists} == "false" ]] && (
	writeErr "No base VM found at path ${baseVMIPath}"
	exit 1
)

if [[ ! ${powerState} == "poweredOff" ]]; then
	echo "--------------------------------------------------------"
	echo "Powering off base VM"
	echo "--------------------------------------------------------"

	if ! powerOffVM "${baseVMIPath}" ${timeout}; then
		writeErr "powering on VM ${baseVMIPath}"
		exit 1
	fi
fi

echo "--------------------------------------------------------"
echo "Destroy Stembuild VM ${stembuild_vm_name} if already exists"
echo "--------------------------------------------------------"

stembuildVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${stembuild_vm_name}")
destroyVM "${stembuildVMIPath}"

echo "--------------------------------------------------------"
echo "Clone Base VM"
echo "--------------------------------------------------------"

if ! clonevm \
	"${stembuild_vm_name}" \
	"${vm_datastore}" \
	"${vm_folder}" \
	"${vm_host}" \
	"${vm_resource_pool}" \
	"${vm_network}" \
	"${vm_cpu}" \
	"${vm_memory_mb}" \
	"${base_vm_name}"; then
	writeErr "cloning base vm"
	exit 1
else
	echo "Done"
fi

#######################################
#       Return result
#######################################
exit 0
