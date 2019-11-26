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
[[ -z "${admin_password}" ]] && (echo "admin_password is a required value" && exit 1)

#######################################
#       Default optional
#######################################
vcenter_ca_certs=${vcenter_ca_certs:=''}

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

baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")

#Look for base VM
echo "--------------------------------------------------------"
echo "Validate and power on VM"
echo "--------------------------------------------------------"
if ! exists=$(vmExists "${baseVMIPath}"); then
	writeErr "could not look for base VM at path ${baseVMIPath}"
	exit 1
fi

[[ ${exists} == "false" ]] && (
	writeErr "no base VM found at path ${baseVMIPath}"
	exit 1
)

if ! powerOnVM "${baseVMIPath}"; then
	writeErr "powering on VM ${base_vm_name}"
	exit 1
else
	echo "Done"
fi

echo "--------------------------------------------------------"
echo "waiting for tools online on VM ${base_vm_name}"
echo "--------------------------------------------------------"

while [[ $(getToolsStatus "${baseVMIPath}" ) != 'toolsOk' ]]
do	
	printf .
	sleep 10
done

echo 
echo "--------------------------------------------------------"
echo "Tools Running on VM ${base_vm_name}"
echo "--------------------------------------------------------"

echo "--------------------------------------------------------"
echo "Running windows update"
echo "--------------------------------------------------------"
echo -ne "|"
for ((i = 1; i <= 3; i++)); do
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

echo "--------------------------------------------------------"
echo "waiting for tools offline on VM ${base_vm_name}"
echo "--------------------------------------------------------"

while [[ $(getToolsStatus "${baseVMIPath}" ) != 'toolsNotRunning' ]]
do	
	printf .
	sleep 2
done

echo 
echo "--------------------------------------------------------"
echo "Tools stopped on ${base_vm_name}"
echo "--------------------------------------------------------"

echo "--------------------------------------------------------"
echo "waiting for tools online on VM ${base_vm_name}"
echo "--------------------------------------------------------"

while [[ $(getToolsStatus "${baseVMIPath}" ) != 'toolsOk' ]]
do	
	printf .
	sleep 10
done

echo 
echo "--------------------------------------------------------"
echo "Tools Running on VM ${base_vm_name}"
echo "--------------------------------------------------------"

echo "|"

if ! retryop "shutdownVM '${baseVMIPath}'" 6 10; then
	writeErr "shutdown vm"
	exit 1
else
	echo "Done"
fi

#######################################
#       Return result
#######################################
exit 0
