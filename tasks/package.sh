#!/bin/bash

set -e
set -o errtrace

export ROOT_FOLDER
export THIS_FOLDER

ROOT_FOLDER="$( pwd )"
THIS_FOLDER="$( dirname "${BASH_SOURCE[0]}" )"

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
use_cert=${use_cert:='false'}
cert_path=${cert_path:=''}

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
	writeErr "no VM found for package at path ${iPath}"
	exit 1
fi

echo "--------------------------------------------------------"
echo "Start package"
echo "--------------------------------------------------------"
args="-vcenter-url '${vcenter_host}' -vcenter-username '${vcenter_username}' -vcenter-password '${vcenter_password}' -vm-inventory-path '${iPath}'"

[[ ! -z ${cert_path} ]] && args="${args} -vcenter-ca-certs '${cert_path}'"

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