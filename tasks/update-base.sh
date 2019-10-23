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
[[ -z "${admin_password}" ]] && (echo "admin_password is a required value" && exit 1)

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

if ! findFileExpandArchive "${ROOT_FOLDER}/govc/govc_linux_amd64" "${ROOT_FOLDER}/govc/govc_linux_amd64.gz" true; then exit 1; fi
# shellcheck source=./functions/govc.sh
source "${THIS_FOLDER}/functions/govc.sh" \
  -govc "${ROOT_FOLDER}/govc/govc_linux_amd64" \
  -url ${vcenter_url} \
  -username ${vcenter_username} \
  -password ${vcenter_password} \
	-use-cert ${use_cert} \
	-cert-path ${cert_path}

#######################################
#       Begin task
#######################################
#set -x #echo all commands

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")

#Look for base VM
echo "--------------------------------------------------------"
echo "Validate and power on VM"
echo "--------------------------------------------------------"
if ! exists=$(vmExists "${baseVMIPath}"); then
	writeErr "could not look for base VM at path ${baseVMIPath}"
	exit 1
fi

[[ ${exists} == "false" ]] && (writeErr "no base VM found at path ${baseVMIPath}"; exit 1)

if ! powerOnVM "${baseVMIPath}"; then
  writeErr "powering on VM"
  exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "Running windows update"
echo "--------------------------------------------------------"
echo -ne "|"
for ((i = 1 ; i <= 3 ; i++)); do
	if ! exitCode=$(powershellCmd "${baseVMIPath}" "administrator" "${admin_password}" "Get-WUInstall -AcceptAll -IgnoreReboot"); then
		writeErr "could not run windows update"
		exit 1
	fi
  
	if [[ ${exitCode} == "1" ]]; then
		writeErr "windows update process exited with error"
		exit 1
	fi

	if ! restartVM "${baseVMIPath}"; then
		writeErr "could not restart VM"
		exit 1
	fi

	echo -ne "."
done

echo "|"

if ! powerOffVM "${baseVMIPath}"; then
  writeErr "powering off VM"
  exit 1
else
	echo "Done"
fi

#######################################
#       Return result
#######################################
exit 0