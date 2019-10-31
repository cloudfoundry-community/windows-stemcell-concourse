#!/bin/bash
#
# Task Description:
#   Format autounattend xml. 
#
#

######################################
# Description:
# 	
# Globals:
#		None
# Source Arguments:
#		None
#	Global Returns:
#   None
# Returns:
#   0: success
#   1: error
#######################################
function formatAutoUnattend(){
	local unattend_path="${1}"
	local operating_system_name=${2}
	local language=${3}
	local product_key="${4}"
  local ip_address="${5}"
  local gateway_address="${6}"
  local dns_address="${7}"
  local admin_password="${8}"
  local vmware_tools_uri="${9}"
  local windows_update_module_uri="${10}"

  windowTempPath='C:/Windows/Temp' #assuming all commands are run in powershell, so / will be converted to \
  command_cnt=1
  sync_commands=""

  if ! sync_commands=${sync_commands}$(buildDownloadCommand ${command_cnt} "Download VMWare Tools" "${vmware_tools_uri}" "${windowTempPath}/vmware-tools.exe" Never); then
		writeErr "Could not set sync command for downloading VMWare tools"
		return 1
	fi
  
  (( command_cnt++ ))
  if ! sync_commands=${sync_commands}$(buildDownloadCommand ${command_cnt} "Download WU Powershell Module" "${windows_update_module_uri}" "${windowTempPath}/PSWindowsUpdate.zip" Never); then
		writeErr "Could not set sync command for downloading powershell module"
		return 1
	fi
  
  (( command_cnt++ ))
  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Copy OOBE Unattend" "copy a:/unattend.xml c:/windows/system32/sysprep/unattend.xml" Never); then
		writeErr "Could not set sync command for downloading OOBE unattend"
		return 1
	fi
  
  #VMWare tools silent install is running in the background.
	# ADDLOCAL=ALL REMOVE=Audio,BootCamp,Sync,Hgfs,VMXNet,VMXNet3,VSS
  (( command_cnt++ ))
  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Install VMWare Tools" "Invoke-Command -ScriptBlock {Start-Process ${windowTempPath}/vmware-tools.exe -ArgumentList '/S /v \"/qn REBOOT=R\"' -Wait}" Never); then
		writeErr "Could not set sync command for installing VMWare tools"
		return 1
	fi
  
  (( command_cnt++ ))
  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Install WU Powershell Modules" "Expand-Archive -Path ${windowTempPath}/PSWindowsUpdate.zip -DestinationPath C:/Windows/System32/WindowsPowerShell/v1.0/Modules" Never); then
		writeErr "Could not set sync command for installing powershell modules"
		return 1
	fi
  
#  (( command_cnt++ ))
#  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Install Windows Updates 1 of 3" "Get-WUInstall -AcceptAll -IgnoreReboot" Always); then
#		writeErr "Could not set sync command for installing win updates 1"
#		return 1
#	fi
  
#  (( command_cnt++ ))
#  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Install Windows Updates 2 of 3" "Get-WUInstall -AcceptAll -IgnoreReboot" Always); then
#		writeErr "Could not set sync command for installing win updates 2"
#		return 1
#	fi
  
#  (( command_cnt++ ))
#  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Install Windows Updates 3 of 3" "Get-WUInstall -AcceptAll -IgnoreReboot" Always); then
#		writeErr "Could not set sync command for installing win updates 3"
#		return 1
#	fi
  
  (( command_cnt++ ))
  if ! sync_commands=${sync_commands}$(buildPowershellCommand ${command_cnt} "Prepare OOBE" "C:/Windows/System32/Sysprep/sysprep.exe /oobe /shutdown /unattend:c:/windows/system32/sysprep/unattend.xml" OnRequest); then
		writeErr "Could not set sync command for prepping OOBE"
		return 1
	fi
  
  if ! sed -i -e "s~{{SYNCHRONOUS_COMMANDS}}~${sync_commands}~" \
			-e "s|{{OPERATING_SYSTEM}}|${operating_system_name}|" \
			-e "s|{{LANGUAGE}}|${language}|" \
			-e "s|{{VM_IP}}|${ip_address}|" \
			-e "s|{{VM_GATEWAY_IP}}|${gateway_address}|" \
			-e "s|{{VM_DNS_IP}}|${dns_address}|" \
			${unattend_path}; then
		writeErr "could not format ${unattend_path} correctly with required params"
		return 1
	fi

	# optionally add in the product key if set by user
	if [[ -n "${product_key}" ]]; then
		if ! xmlstarlet ed --inplace -N u="urn:schemas-microsoft-com:unattend" \
				-s "//u:component[@name='Microsoft-Windows-Setup']/u:UserData" \
				-t elem -n ProductKey -v "" \
				-s "//u:component[@name='Microsoft-Windows-Setup']/u:UserData/ProductKey" \
				-t elem -n WillShowUI -v "OnError" \
				-s "//u:component[@name='Microsoft-Windows-Setup']/u:UserData/ProductKey" \
				-t elem -n Key -v "${product_key}" \
				"${unattend_path}"; then
			writeErr "could not insert product key into ${unattend_path}"
			return 1
		fi
	fi

	return 0
}

######################################
# Description: Formats the OOBE unattend.xml replacing placeholders with real
# values.
# 	
# Arguments: 
#		
#######################################
function formatAutoUnattend(){
	local unattend_path="${1}"
	local language=${2}
	local admin_password="${3}"
  
	if ! sed -i -e "s|{{ADMINISTRATOR_PASSWORD}}|${admin_password}|" \
			-e "s|{{LANGUAGE}}|${language}|" \
			${unattend_path}; then
		writeErr "could not format ${unattend_path} correctly with required params"
		return 1
	fi

	return 0
}

function buildDownloadCommand(){
	local order="${1}"
	local description=${2}
	local uri="${3}"
	local out_file="${4}"
	local will_reboot="${5}"

  sed -e "s~{{order}}~${order}~" -e "s~{{description}}~${description}~" -e "s~{{uri}}~${uri}~" -e "s~{{out_file}}~${out_file}~" -e "s~{{will_reboot}}~${will_reboot}~" ${THIS_FOLDER}/functions/sync-cmd-download.xml
  
  return 0
}

function buildPowershellCommand(){
	local order="${1}"
	local description=${2}
	local path="${3}"
	local will_reboot="${4}"

  sed -e "s~{{order}}~${order}~" -e "s~{{description}}~${description}~" -e "s~{{path}}~${path}~" -e "s~{{will_reboot}}~${will_reboot}~" ${THIS_FOLDER}/functions/sync-cmd-ps.xml
  
  return 0
}

function buildPSFileCommand(){
	local order="${1}"
	local description=${2}
	local path="${3}"
	local will_reboot="${4}"

  sed -e "s|{{order}}|${order}|" -e "s|{{description}}|${description}|" -e "s|{{path}}|${path}|" -e "s|{{will_reboot}}|${will_reboot}|" ${THIS_FOLDER}/functions/sync-cmd-psfile.xml
  
  return 0
}