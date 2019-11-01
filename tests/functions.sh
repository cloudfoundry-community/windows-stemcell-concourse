#!/bin/bash

set -o errexit
set -o errtrace

function read_dom() {
	ORIGINAL_IFS=$IFS
	IFS=\>
	read -d \< ENTITY CONTENT
	local ret=$?
	#TAG_NAME=${ENTITY%% *}
	#ATTRIBUTES=${ENTITY#* }
	IFS=$ORIGINAL_IFS
	return $ret
}

function echoerr() {
	echo "ERROR: $*"
	date -u
}

function echosuccess() {
	echo "[SUCCESS] $*"
	date -u
}

function testAutoUnattend() {
	local unattend_path="${1}"

	echo "Formatting xml"
	if ! formatAutoUnattend \
		"${unattend_path}" \
		"${operating_system_name}" \
		"${language}" \
		"${product_key}" \
		"${ip_address}" \
		"${gateway_address}" \
		"${dns_address}" \
		"${vmware_tools_uri}" \
		"${windows_update_module_uri}"; then
		echoerr "formatting autounattend"
		return 1
	fi

	echo "Validating formatted xml"
	while read_dom; do
		if [[ -z $(echo -e "${CONTENT}" | tr -d '[:space:]') ]]; then
			continue
		fi

		echo -ne "."

		#echo "$ENTITY => $CONTENT"
		if [[ ${CONTENT} == *'{{OPERATING_SYSTEM}}'* ]]; then
			echoerr "Autounattend not formatted correctly - OPERATING_SYSTEM"
			return 1
		elif [[ ${CONTENT} == *'{{PRODUCT_KEY}}'* ]]; then
			echoerr "Autounattend not formatted correctly - PRODUCT_KEY"
			return 1
		elif [[ ${CONTENT} == *'{{SYNCHRONOUS_COMMANDS}}'* ]]; then
			echoerr "Autounattend not formatted correctly - SYNCHRONOUS_COMMANDS"
			return 1
		elif [[ ${CONTENT} == *'{{LANGUAGE}}'* ]]; then
			echoerr "Autounattend not formatted correctly - LANGUAGE"
			return 1
		elif [[ ${CONTENT} == *'{{VM_IP}}'* ]]; then
			echoerr "Autounattend not formatted correctly - VM_IP"
			return 1
		elif [[ ${CONTENT} == *'{{VM_GATEWAY_IP}}'* ]]; then
			echoerr "Autounattend not formatted correctly - VM_GATEWAY_IP"
			return 1
		elif [[ ${CONTENT} == *'{{VM_DNS_IP}}'* ]]; then
			echoerr "Autounattend not formatted correctly - VM_DNS_IP"
			return 1
		elif [[ ${CONTENT} == *'C:WindowsTemp'* ]]; then
			echoerr "Autounattend not formatted correctly - Windows temp folder path"
			return 1
		fi
	done <"${unattend_path}"

	return 0
}

function testCreateISO() {
	local isoPath="${1}"
	local extractISOPath="${2}"
	local finalIsoFilePath="${3}"
	local autounattendPath="${4}"

	if ! sudo 7z x -y -bsp1 -o${extractISOPath} "${isoPath}"; then
		echoerr "expanding iso"
		return 1
	fi

	sudo cp "${autounattendPath}" "${extractISOPath}/autounattend.xml"

	if ! sudo mkisofs -quiet \
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
		echoerr "creating new ISO"
		return 1
	fi

	return 0
}

function testUploadToDatastore() {
	local iso_nm="${1}"
	local finalIsoFilePath="${2}"

	if ! uploadToDatastore "${finalIsoFilePath}" "${iso_datastore}" "${iso_folder}/${iso_nm}"; then
		echoerr "uploading iso to datastore"
		return 1
	fi

	return 0
}

function testCreateVMwithISO() {
	local iPath="${1}"
	local vm_nm="${2}"
	local iso_path="${3}"

	if ! createVMwithISO "${vm_nm}" \
		"${vm_datastore}" \
		"${vm_host}" \
		"${vm_network}" \
		${vm_cpu} \
		${vm_memory_mb} \
		${vm_disk_gb} \
		"${vm_folder}" \
		"${vm_guest_os_id}" \
		"${iso_datastore}" \
		"${iso_path}" \
		"${vm_net_adapter}" \
		"${esxi_version}" \
		"${firmware_type}" \
		"${disk_controller_type}" \
		"${vm_resource_pool}" \
		"${vcenter_datacenter}"; then
		return 1
	fi

	if ! exists=$(vmExists ${iPath}); then
		echo ${exists}
		return 1
	fi
	if [[ ${exists} == "false" ]]; then
		echoerr "could not find vm at ${iPath}"
		return 1
	fi

	if ! powerState=$(getPowerState ${iPath}); then
		echo "${powerState}"
		return 1
	fi
	if [[ "${powerState}" == *"poweredOn"* ]]; then
		echoerr "vm should not be powered on"
		return 1
	fi

	return 0
}

function testSetBootOrder() {
	local iPath="${1}"

	if ! setBootOrder "${iPath}"; then
		echoerr "setting boot order"
		return 1
	fi

	return 0
}

function testConnectDevice() {
	local iPath="${1}"
	local device_name="${2}"

	if ! connectDevice "${iPath}" "${device_name}"; then
		echoerr "connecting device"
		return 1
	fi

	return 0
}

function testPowerOnToInstallWindows() {
	local iPath="${1}"

	if ! powerOnVM "${iPath}"; then
		echoerr "powering on VM"
		return 1
	fi

	echo -ne "Installing windows "
	while [[ $(getPowerState "${iPath}") == *"poweredOn"* ]]; do
		echo -ne "."
		sleep 2m
	done

	return 0
}

function testEjectCDRom() {
	local iPath="${1}"

	if ! ejectCDRom ${iPath}; then
		echoerr "ejecting cd rom"
		return 1
	fi
}

function testValidateAndPowerOff() {
	local iPath="${1}"

	if ! validateAndPowerOff "${iPath}"; then
		echoerr "could not validate base vm ${iPath}"
		return 1
	fi
}

function testCloneVM() {
	local new_vm_name="${1}"
	local vm_to_clone_name="${2}"

	if ! clonevm \
		"${new_vm_name}" \
		"${vm_datastore}" \
		"${vm_folder}" \
		"${vm_host}" \
		"${vm_resource_pool}" \
		"${vm_network}" \
		"${vm_cpu}" \
		"${vm_memory_mb}" \
		"${vm_to_clone_name}"; then
		echoerr "cloning base vm"
		exit 1
	fi
}

function testConstruct() {
	local iPath="${1}"
	local stembuildPath="${2}"
	local lgpoPath="${3}"

	cp "${lgpoPath}" ./LGPO.zip

	args="-vm-ip '${ip_address}' -vm-username 'administrator' -vm-password '${admin_password}'  -vcenter-url '${vcenter_host}' -vcenter-username '${vcenter_username}' -vcenter-password '${vcenter_password}' -vm-inventory-path '${iPath}' -vcenter-ca-certs '${cert_path}'"

	cmd="sudo ${stembuildPath} construct ${args}"

	echo "${cmd}"
	if ! eval ${cmd}; then
		echoerr "running construct"
		return 1
	fi

	echo -ne "Running construct "
	while [[ $(getPowerState "${iPath}") == *"poweredOn"* ]]; do
		echo -ne "."
		sleep 2m
	done

	return 0
}

function testPackage() {
	local iPath="${1}"
	local stembuildPath="${2}"

	args="-vcenter-url '${vcenter_host}' -vcenter-username '${vcenter_username}' -vcenter-password '${vcenter_password}' -vm-inventory-path '${iPath}' -vcenter-ca-certs '${cert_path}'"

	cmd="sudo ${stembuildPath} package ${args}"

	echo "${cmd}"
	if ! eval ${cmd}; then
		echoerr "running package"
		return 1
	fi

	return 0
}
#function lookupDevice(){
#sudo -E govc/govc_linux_amd64 device.ls -vm Win-Stemcell-Base -json
#}
#function validateVMDevice(){
#sudo -E govc/govc_linux_amd64 device.info -vm Win-Stemcell-Base cdrom-*
#}

#===============================================================================
# SOURCE SCRIPTS
#===============================================================================
# shellcheck source=../tasks/functions/utility.sh
source "${THIS_FOLDER}/functions/utility.sh"
# shellcheck source=../tasks/functions/autounattend.sh
source "${THIS_FOLDER}/functions/autounattend.sh"
# shellcheck source=../tasks/functions/govc.sh
source "${THIS_FOLDER}/functions/govc.sh" \
	-govc "sudo -E $(find ${ROOT_FOLDER}/govc/govc_linux_* 2>/dev/null | head -n1)" \
	-url "${vcenter_host}" \
	-username "${vcenter_username}" \
	-password "${vcenter_password}" \
	-use-cert "${use_cert}" \
	-cert-path "${cert_path}"

#===============================================================================
# VARIABLES
#===============================================================================
isoTmpFolder="/mnt/formatIso"
isoTmpPath="/tmp/final-iso.iso"

folderIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}")
baseVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${base_vm_name}")

isoPath="$(find "${ROOT_FOLDER}/iso" -iname *.iso 2>/dev/null | head -n1)"
autounattendPath="${ROOT_FOLDER}/autounattend/test-autounattend.xml"
stembuildPath="$(find ${ROOT_FOLDER}/stembuild -iname stembuild-linux-x86_64-* 2>/dev/null | head -n1)"
lgpoPath="${ROOT_FOLDER}/lgpo/LGPO.zip"

vers=$(${stembuildPath} -v)
if ! stembuild_vm_name=$(parseStembuildVersion "${vers}"); then
	echo "[ERROR] trying to parse stembuild version"
	exit 1
fi

stembuildVMIPath=$(buildIpath "${vcenter_datacenter}" "${vm_folder}" "${stembuild_vm_name}")

#===============================================================================
# FUNCTION TESTS
#===============================================================================
date -u

#create a temp file
[[ ! -d "${ROOT_FOLDER}/autounattend" ]] && mkdir "${ROOT_FOLDER}/autounattend"
cp "${THIS_FOLDER}/assets/autounattend.xml" "${autounattendPath}"

if ! testAutoUnattend "${autounattendPath}"; then
	echo "[ERROR] Testing autounattend"
	exit 1
else
	echosuccess "Created autounattend"
fi

sudo apt-get update && sudo apt-get -y install genisoimage
sudo mkisofs -version

if ! testCreateISO "${isoPath}" "${isoTmpFolder}" "${isoTmpPath}" "${testAutounattendPath}"; then
	echo "[ERROR] Testing create ISO"
	exit 1
else
	echosuccess "ISO created"
fi

if ! testUploadToDatastore "${base_vm_name}.iso" "${isoTmpPath}"; then
	echo "[ERROR] Testing uploadToDatastore"
	exit 1
else
	echosuccess "Uploaded to datastore"
fi

if ! testCreateVMwithISO "${baseVMIPath}" "${base_vm_name}" "${iso_folder}/${base_vm_name}.iso"; then
	echo "[ERROR] Testing createVMwithISO"
	exit 1
else
	echosuccess "VM Successfully created and validated"
fi

if ! testConnectDevice "${baseVMIPath}" "cdrom-3000"; then
	echo "[ERROR] Testing testConnectDevice"
	exit 1
else
	echosuccess "Connected device"
fi

if ! testSetBootOrder "${baseVMIPath}"; then
	echo "[ERROR] Testing boot order"
	exit 1
else
	echosuccess "Boot order validated"
fi

if ! testPowerOnToInstallWindows "${baseVMIPath}"; then
	echo "[ERROR] Testing poweron to install windows"
	exit 1
else
	echosuccess "Installed windows"
fi

if ! testEjectCDRom "${baseVMIPath}"; then
	echo "[ERROR] Testing eject CD rom"
	exit 1
else
	echosuccess "Ejected CD rom"
fi

if ! testValidateAndPowerOff "${baseVMIPath}"; then
	echo "[ERROR] Testing validate and power off"
	exit 1
else
	echosuccess "VM validated and powered off"
fi

if ! testCloneVM "${stembuild_vm_name}" "${base_vm_name}"; then
	echo "[ERROR] Testing clone VM"
	exit 1
else
	echosuccess "Cloned VM"
fi

if ! powerOnVM "${stembuildVMIPath}"; then
	echoerr "powering on VM for construct"
	return 1
else
	sleep 30s #let the VM get started
fi

if ! testConstruct "${stembuildVMIPath}" "${stembuildPath}" "${lgpoPath}"; then
	echo "[ERROR] Testing stembuild construct"
	exit 1
else
	echosuccess "Ran stembuild construct"
fi

if ! testPackage "${stembuildVMIPath}" "${stembuildPath}"; then
	echo "[ERROR] Testing stembuild package"
	exit 1
else
	echosuccess "Ran stembuild package"
fi

#Cleanup
sudo rm -rdf "${isoTmpFolder}"
sudo rm "${isoTmpPath}"
sudo rm "${testAutounattendPath}"
sudo rm ./LGPO.zip
#destroyVM "${baseVMIPath}"
#destroyVM "${stembuildVMIPath}"

date -u

exit 0
