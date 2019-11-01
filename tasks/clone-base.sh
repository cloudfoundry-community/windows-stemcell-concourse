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
use_cert=${use_cert:='false'}
cert_path=${cert_path:=''}
vm_network=${vm_network:='VM Network'}
vm_cpu=${vm_cpu:=4}
vm_memory_mb=${vm_memory_mb:=8000}
vm_resource_pool=${vm_resource_pool:=''}

if [[ ! -z "${vcenter_ca_certs}" ]]; then
	use_cert="true"

	#write the cert to file locally
	(echo ${vcenter_ca_certs} | awk '
		match($0,/- .* -/){
			val=substr($0,RSTART,RLENGTH)
			gsub(/- | -/,"",val)
			gsub(OFS,ORS,val)
			print substr($0,1,RSTART) ORS val ORS substr($0,RSTART+RLENGTH-1)}') >${ROOT_FOLDER}/cert.crt

	cert_path=${ROOT_FOLDER}/cert.crt
fi

#######################################
#       Source helper functions
#######################################
# shellcheck source=./functions/utility.sh
source "${THIS_FOLDER}/functions/utility.sh"

if ! findFileExpandArchive "${ROOT_FOLDER}/govc/govc_linux_amd64" "${ROOT_FOLDER}/govc/govc_linux_amd64.gz" true; then exit 1; fi
# shellcheck source=./functions/govc.sh
source "${THIS_FOLDER}/functions/govc.sh" \
	-govc "${ROOT_FOLDER}/govc/govc_linux_amd64" \
	-url "${vcenter_host}" \
	-username "${vcenter_username}" \
	-password "${vcenter_password}" \
	-use-cert "${use_cert}" \
	-cert-path "${cert_path}" || (writeErr "error initializing govc" && exit 1)

#######################################
#       Begin task
#######################################

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

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")
if ! vmExists "${baseVMIPath}"; then
	writeErr "base VM found not found for clone at path ${iPath}"
	exit 1
fi

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
