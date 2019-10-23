###########################################################
#AWS S3 BUCKET [https://docs.aws.amazon.com/powershell/index.html]
###########################################################
New-S3Bucket -BucketName "windows-stemcell-concourse"
Write-S3BucketVersioning -BucketName "windows-stemcell-concourse" -VersioningConfig_Status Enabled
Write-S3Object -BucketName "windows-stemcell-concourse/lgpo" -File C:\<PATH_TO_LGPO>\LGPO.zip
Write-S3Object -BucketName "windows-stemcell-concourse/iso" -File C:\<PATH_TO_MY_ISO>.iso
Write-S3Object -BucketName "windows-stemcell-concourse/autounattend" -File C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\assets\autounattend.xml

###########################################################
#SET CONCOURSE PIPELINE (don't forget to fill in values in vars-min.yml)
###########################################################
fly -t <MY_CONCOURSE_TARGET> set-pipeline `
   --pipeline create-windows-stemcell `
   --config C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\pipeline.yml `
	 --load-vars-from C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\vars-min.yml

###########################################################
#GET VCENTER CERTIFICATES & PRINT THE FIRST ONE
###########################################################
Invoke-WebRequest -Uri https://<MY_VCENTER_ADDRESS>/certs/download.zip -OutFile C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\certs.zip
Expand-Archive -Path C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\certs.zip -DestinationPath C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\certs
Get-ChildItem -Path C:\<PATH_TO_CLONED_REPO>\windows-stemcell-concourse\certs -Recurse -File | Select-Object -First 1