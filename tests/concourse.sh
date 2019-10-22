#!/bin/bash
set -o errexit
set -o errtrace

ROOT_FOLDER=/mnt/c/Users/ddieruf/source/stemcell-concourse
THIS_FOLDER=/mnt/c/Users/ddieruf/source/stemcell-concourse/tests

date -u
cp "${ROOT_FOLDER}/assets/autounattend.xml" "${THIS_FOLDER}/autounattend/autounattend.xml"

fly -t con execute \
    -c ${ROOT_FOLDER}/tasks/create-base.yml \
    -i pipeline-resources=${ROOT_FOLDER} \
    -i govc=${THIS_FOLDER}/govc \
    -i autounattend=${THIS_FOLDER}/autounattend \
    -i iso=${THIS_FOLDER}/iso \
    -l ${ROOT_FOLDER}/vars/my-vars.yml \
		--privileged

date -u

fly -t con execute \
    -c ${ROOT_FOLDER}/tasks/clone-base.yml \
    -i pipeline-resources=${ROOT_FOLDER} \
    -i govc=${THIS_FOLDER}/govc \
    -i stembuild=${THIS_FOLDER}/stembuild \
    -l ${ROOT_FOLDER}/vars/my-vars.yml \
		--privileged

date -u

fly -t con execute \
    -c ${ROOT_FOLDER}/tasks/construct.yml \
    -i pipeline-resources=${ROOT_FOLDER} \
    -i govc=${THIS_FOLDER}/govc \
    -i stembuild=${THIS_FOLDER}/stembuild \
    -i lgpo=${THIS_FOLDER}/lgpo \
    -l ${ROOT_FOLDER}/vars/my-vars.yml \
		--privileged

date -u

fly -t con execute \
    -c ${ROOT_FOLDER}/tasks/package.yml \
    -i pipeline-resources=${ROOT_FOLDER} \
    -i govc=${THIS_FOLDER}/govc \
    -i stembuild=${THIS_FOLDER}/stembuild \
    -l ${ROOT_FOLDER}/vars/my-vars.yml \
		--output stemcell=${THIS_FOLDER}/stemcell
		--privileged
		
date -u

fly -t con execute \
    -c ${ROOT_FOLDER}/tasks/update-base.yml \
    -i pipeline-resources=${ROOT_FOLDER} \
    -i govc=${THIS_FOLDER}/govc \
    -l ${ROOT_FOLDER}/vars/my-vars.yml \
		--privileged
		
date -u
rm "${THIS_FOLDER}/autounattend/autounattend.xml"