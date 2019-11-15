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
[[ -z "${ip_address}" ]] && (echo "ip_address is a required value" && exit 1)
[[ -z "${admin_password}" ]] && (echo "admin_password is a required value" && exit 1)

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
			print substr($0,1,RSTART) ORS val ORS substr($0,RSTART+RLENGTH-1)}') >${ROOT_FOLDER}/cert.crt

	cert_path=${ROOT_FOLDER}/cert.crt
fi

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
	writeErr "no VM found for construct at path ${iPath}"
	exit 1
fi

lgpoPath="$(find "${ROOT_FOLDER}/lgpo" -iname lgpo.zip 2>/dev/null | head -n1)"

echo "--------------------------------------------------------"
echo "Verify LGPO"
echo "--------------------------------------------------------"
if [[ -z ${lgpoPath} ]]; then
	writeErr "No LGPO.zip file found in input."
	echo "Contents of lgpo input:"
	ls -al ${ROOT_FOLDER}/lgpo
	exit 1
fi

if [[ ! -f ${lgpoPath} ]]; then
	writeErr "LGPO path invalid = ${lgpoPath}"
	echo "Contents of lgpo input:"
	ls -al ${ROOT_FOLDER}/lgpo
	exit 1
fi

#LGPO needs to be in the working folder (where stembuild is called fom)
cp "${lgpoPath}" ./LGPO.zip
echo "Done"

echo "--------------------------------------------------------"
echo "Start the cloned VM"
echo "--------------------------------------------------------"
if ! powerOnVM "${iPath}"; then
	writeErr "powering on VM for construct"
	return 1
else
	echo "Done"
	sleep 30s #let the VM get started
fi

echo "--------------------------------------------------------"
echo "Start construct"
echo "--------------------------------------------------------"
args="-vm-ip '${ip_address}' -vm-username 'administrator' -vm-password '${admin_password}' -vcenter-url '${vcenter_host}' -vcenter-username '${vcenter_username}' -vcenter-password '${vcenter_password}' -vm-inventory-path '${iPath}'"

[[ ! -z ${cert_path} ]] && args="${args} -vcenter-ca-certs '${cert_path}'"

cmd="${stembuildPath} construct ${args}"

echo "${cmd}"
if ! eval ${cmd}; then
	writeErr "running construct"
	exit 1
fi

#Once the construct process exits, the VM is still doing work. We will know it's done with it shuts off. The following will poll the VM for it's power status.

echo -ne "|"
while [[ $(getPowerState "${iPath}") == *"poweredOn"* ]]; do
	echo -ne "."
	sleep 2m
done

echo "|"
echo "Done"

#######################################
#       Return result
#######################################
exit 0
