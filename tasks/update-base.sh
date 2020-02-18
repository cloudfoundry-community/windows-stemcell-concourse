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
timeout_seconds=${timeout_seconds:=30}

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

if ! powerState=$(getPowerState "${baseVMIPath}"); then
	writeErr "could not get power state for VM at path ${baseVMIPath}"
	exit 1
fi

echo "Powered state: $powerState"

if [[ ! ${powerState} == "poweredOn" ]]; then
	if ! powerOnVM "${baseVMIPath}" ${timeout_seconds}; then
		writeErr "powering on VM ${base_vm_name}"
		exit 1
	fi
fi

echo "Done"

echo "--------------------------------------------------------"
echo "Running windows update"
echo "--------------------------------------------------------"

for ((i = 1; i <= 3; i++)); do
	echo "    starting ${i}"
	if ! exitCode=$(powershellCmd "${baseVMIPath}" "administrator" "${admin_password}" "Get-WUInstall -AcceptAll -IgnoreReboot"  2>&1); then
		echo "${exitCode}" #write the error echo'd back
		writeErr "could not run windows update"
		exit 1
	fi

	if [[ ${exitCode} == 1 ]]; then
		writeErr "windows update process exited with error"
		exit 1
	fi

	if ! shutdownVM "${baseVMIPath}" ${timeout_seconds}; then
		writeErr "could not shutdown VM"
		exit 1
	fi

	if ! powerOnVM "${baseVMIPath}" ${timeout_seconds}; then
		writeErr "${ret}"
		exit 1
	fi

	echo "    finished ${i}"
done

echo "--------------------------------------------------------"
echo "Updates done, shutting down"
echo "--------------------------------------------------------"
if ! shutdownVM "${baseVMIPath}" ${timeout_seconds}; then
	writeErr "could not shutdown vm"
	exit 1
fi

echo "Done"

#######################################
#       Return result
#######################################
exit 0
