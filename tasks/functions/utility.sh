#!/bin/bash

#
# Task Description:
#   Odd utlity functions to make life easier. 
#
#

######################################
# Description: Installs file system tools used to create a floppy img
# 	
# Arguments:
#		None
#######################################
function installFsTools(){
	apt-get -y install dosfstools mtools

	return 0
}

######################################
# Description: Installs xmlstartlet to manipulate xml docs
# 	
# Arguments:
#		None
#######################################
function installXmlstarlet(){
	apt-get -y install xmlstarlet

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		None
#######################################
function installcurl(){
  	apt-get -y install curl

	return 0
}

######################################
# Description:
# 	Install jq
# Arguments:
#		None
#######################################
function installjq(){
	apt-get -y install jq

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		None
#######################################
function writeErr() {
	local msg="${1}"
	echo "[ERROR]: ${msg}"
}

######################################
# Description: Converts a subnet mask to CIDR notation
# 	
# Arguments:
#		None Subnet mask, i.e. 255.255.255.0
#######################################
subnetMaskToCidr ()
{
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) "${x%%.*}"
   x=${1%%$3*}
   echo $(( $2 + (${#x}/4) ))
}

######################################
# Description:
# 	
# Arguments:
#		None
#######################################
function findFileExpandArchive(){
	local filePath="${1}"
	local archivePath="${2}"
	local asExecutable="${3}"

	file=$(find "${filePath}" 2>/dev/null | head -n1)
	if [[ -z ${file} ]]; then
		archive=$(find "${archivePath}" 2>/dev/null | head -n1)
		if [[ -z ${archive} ]]; then
			writeErr "no archive found at path ${archivePath}"
			return 1
		else
			gunzip "${archivePath}"
		fi

		file2=$(find "${filePath}" 2>/dev/null | head -n1)
		if [[ -z ${file2} ]]; then
			writeErr "could not find file '${filePath}' after expanding archive at '${archivePath}'"
			return 1
		fi
	fi

	[[ ${asExecutable} == true ]] && chmod +x ${filePath}

	return 0
}

######################################
# Description:
# 	
# Arguments:
#		None
#######################################
function parseStembuildVersion() {
	local stembuildVersionOutput="${1}"
	#stembuild-linux-x86_64-2019.12 version 2019.12.26, Windows Stemcell Building Tool
	vars=( ${stembuildVersionOutput} )

	if [[ ${#vars[@]} -lt 3 ]]; then
		writeErr "parsing stembuild version from string '${stembuildVersionOutput}'"
		return 1
	fi

	versionNums=${vars[2]}
	majorNum=$(cut -d '.' -f 1 <<<"${versionNums}")
	minorNum=$(cut -d '.' -f 2 <<<"${versionNums}")

	if [[ -z ${majorNum} ]]; then
		writeErr "could not found stembuild major version number from '${versionNums}'"
		return 1
	fi

	if [[ -z ${minorNum} ]]; then
		writeErr "could not found stembuild minor version number from '${versionNums}'"
		return 1
	fi

	echo "${majorNum}.${minorNum}"

	return 0
}

#######################################
#       Install Dependencies
#######################################
apt-get update
#sudo apt-get install software-properties-common
#add-apt-repository universe
command -v jq >/dev/null 2>&1 || installjq
command -v xml >/dev/null 2>&1 || installXmlstarlet
command -v mcopy >/dev/null 2>&1 || installFsTools
command -v curl >/dev/null 2>&1 || installcurl
