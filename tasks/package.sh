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
[[ -z "${vm_folder}" ]] && (echo "vm_folder is a required value" && exit 1)

[[ ! -d "${ROOT_FOLDER}/stembuild" ]] && (echo "expecting stembuild binary to be at ${ROOT_FOLDER}/stembuild" && exit 1)
[[ ! -d "${ROOT_FOLDER}/stemcell" ]] && (echo "expecting stemcell dir to be at ${ROOT_FOLDER}/stemcell" && exit 1)

#######################################
#       Default optional
#######################################
vcenter_ca_certs=${vcenter_ca_certs:=''}
timeout=${timeout:=1m}
vmware_tools_status=${vmware_tools_status:='current'}

#######################################
#       Source helper functions
#######################################
source "${THIS_FOLDER}/functions/utility.sh"
source "${THIS_FOLDER}/functions/govc.sh"

if ! initializeGovc "${vcenter_host}" \
	"${vcenter_username}" \
	"${vcenter_password}" \
	"${vcenter_ca_certs}" \
	"${vcenter_datacenter}"; then
	writeErr "error initializing govc"
	exit 1
fi

#######################################
#       Begin task
#######################################
#set -x #echo all commands

stembuildPath="$(find "${ROOT_FOLDER}/stembuild" -iname stembuild-linux-* 2>/dev/null | head -n1)"
[[ ! -f "${stembuildPath}" ]] && (writeErr "stembuild-linux-* not found in ${stembuildPath}" && exit 1)

chmod +x ${stembuildPath}

if [[ -z "${stembuild_vm_name}" ]]; then
	vers=$(${stembuildPath} -v)
	if ! stembuild_vm_name=$(parseStembuildVersion "${vers}"); then
		writeErr "trying to parse stembuild version"
		exit 1
	fi
fi

iPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${stembuild_vm_name}")
if ! vmExists "${iPath}"; then
	writeErr "no VM found at path ${iPath}"
	exit 1
fi

echo "--------------------------------------------------------"
echo "Start package"
echo "--------------------------------------------------------"
args="-vcenter-url '${vcenter_host}' -vcenter-username '${vcenter_username}' -vcenter-password '${vcenter_password}' -vm-inventory-path '${iPath}'"

[[ ${GOVC_INSECURE} -eq 0 ]] && args="${args} -vcenter-ca-certs '${GOVC_TLS_CA_CERTS}'"

cmd="${stembuildPath} package ${args}"

echo "${cmd}"
if ! eval ${cmd}; then
	writeErr "running package"
	exit 1
fi

echo "--------------------------------------------------------"
echo "Move final stemcell"
echo "--------------------------------------------------------"

stemcell_file="$(find *.tgz 2>/dev/null | head -n1)"

if [[ ! -f "${stemcell_file}" ]]; then
	writeErr "No stemcell file found."
	echo "Contents of dir:"
	ls -al .
	exit 1
fi

mv ${stemcell_file} "${ROOT_FOLDER}/stemcell/${stemcell_file}"
echo "Done"

#######################################
#       Return result
#######################################
exit 0
