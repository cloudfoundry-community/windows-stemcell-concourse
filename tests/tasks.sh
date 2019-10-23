#!/bin/bash

set -e
set -o errtrace

function cleanupTests(){
	#reset the autounattend file to template
	sudo rm "${ROOT_FOLDER}/autounattend/autounattend.xml"

	#remove formatted ISO folder
	sudo rm -rdf /mnt/formatIso

	#remove ISO file
	sudo rm /tmp/final-iso.iso
	
	sudo rm "${ROOT_FOLDER}/LGPO.zip"

	#remove stemcell
	#sudo rm "${ROOT_FOLDER}/stemcell/bosh*"
}

#===============================================================================
# TASK SCRIPT TESTS
#===============================================================================
date -u
[[ ! -d "${ROOT_FOLDER}/autounattend" ]] && mkdir "${ROOT_FOLDER}/autounattend"
cp "${THIS_FOLDER}/assets/autounattend.xml" "${ROOT_FOLDER}/autounattend/autounattend.xml"
sudo -E ../tasks/create-base.sh
date -u
sudo -E ../tasks/clone-base.sh
date -u
sudo -E ../tasks/construct.sh
date -u
sudo -E ../tasks/package.sh
date -u
sudo -E ../tasks/update-base.sh
date -u

cleanupTests
exit 0