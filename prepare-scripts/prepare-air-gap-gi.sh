#!/bin/bash

local_directory=`pwd`
host_fqdn=$( hostname --long )
temp_dir=$local_directory/gi-temp
air_dir=$local_directory/air-gap
# Creates target download directory
mkdir -p $temp_dir
# Creates temporary directory
mkdir -p $air_dir
#read -p "Insert RH account name: " rh_account
#read -sp "Insert RH account password: " rh_account_pwd
declare -a gi_versions=(3.0 3.1)
gi_version_selected=1
#while [[ ( -z $gi_version_selected ) || ( $gi_version_selected -lt 1 || $gi_version_selected -gt $i ) ]]
#do
#	echo "Select GI version to mirror:"
#        i=1
#        for gi_version in "${gi_versions[@]}"
#        do
#        	echo "$i - $gi_version"
#                i=$((i+1))
#        done
#        read -p "Your choice?: " gi_version_selected
#done
$gi_version_selected=$(($ics_version_selected-1))
# Gets source bastion release (supported CentOS 8)
dnf -qy install python3 podman wget
# - cleanup repository if exists
podman stop bastion-registry
podman container prune <<< 'Y'
rm -rf /opt/registry
# - Pulls image of portable registry and save it 
podman pull docker.io/library/registry:2
# - Prepares portable registry directory structure
mkdir -p /opt/registry/{auth,certs,data}
# - Creates SSL cert for portable registry (only for mirroring, new one will be created in disconnected env)
openssl req -newkey rsa:4096 -nodes -sha256 -keyout /opt/registry/certs/bastion.repo.pem -x509 -days 365 -out /opt/registry/certs/bastion.repo.crt -subj "/C=PL/ST=Miedzyrzecz/L=/O=Test /OU=Test/CN=`hostname --long`" -addext "subjectAltName = DNS:`hostname --long`"
cp /opt/registry/certs/bastion.repo.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
# - Creates user to get access to portable repository
dnf -qy install httpd-tools
htpasswd -bBc /opt/registry/auth/htpasswd admin guardium
# - Sets firewall settings
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --zone=public --add-port=5000/tcp --permanent
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --reload
# - Sets SE Linux for NetworkManager
semanage permissive -a NetworkManager_t
# - Starts portable registry
podman run -d --name bastion-registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" -e "REGISTRY_HTTP_SECRET=ALongRandomSecretForRegistry" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/bastion.repo.crt -e REGISTRY_HTTP_TLS_KEY=/certs/bastion.repo.pem docker.io/library/registry:2
# Packs together centos updates, packages, python libraries and portable image
cd $air_dir
wget "https://github.com/IBM/cloud-pak-cli/releases/latest/download/cloudctl-linux-amd64.tar.gz" > /dev/null
wget "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/openshift-client-linux.tar.gz"
tar xf cloudctl-linux-amd64.tar.gz -C /usr/local/bin
tar xf openshift-client-linux.tar.gz -C /usr/local/bin
rm -f openshift-client-linux.tar.gz
mv /usr/local/bin/cloudctl-linux-amd64 /usr/local/bin/cloudctl
# Mirrors GI images to portable repository
dnf -qy install jq
b64auth=$( echo -n 'admin:guardium' | openssl base64 )
LOCAL_REGISTRY="$host_fqdn:5000"
# Mirroring ICS images
echo "Mirroring ICS ${ics_versions[${ics_version_selected}]}"
# - install Skopeo utility
dnf -qy install skopeo
# - declares cases files per ICS release
declare -a cases=(ibm-guardium-insights-2.0.0.tgz)
# - declares variables
CASE_ARCHIVE=${cases[${ics_version_selected}]}
CASE_INVENTORY_SETUP=ibmCommonServiceOperatorSetup
# - downloads manifests
cloudctl case save --case https://github.com/IBM/cloud-pak/raw/master/repo/case/${CASE_ARCHIVE} --outputdir $temp_dir/gi_offline
# - authenticates in external repositories
exit 1
sites="cp.icr.io registry.redhat.io registry.access.redhat.com"
for site in $sites
do
	echo $site
        cloudctl case launch --case $temp_dir/ics_offline/${CASE_ARCHIVE} --inventory ${CASE_INVENTORY_SETUP} --action configure-creds-airgap --args "--registry $site --user $rh_account --pass $rh_account_pwd"
done
cloudctl case launch --case $temp_dir/ics_offline/${CASE_ARCHIVE} --inventory ${CASE_INVENTORY_SETUP} --action configure-creds-airgap --args "--registry `hostname --long`:5000 --user admin --pass guardium"
# - mirrors ICS images
cloudctl case launch --case $temp_dir/ics_offline/${CASE_ARCHIVE} --inventory ${CASE_INVENTORY_SETUP} --action mirror-images --args "--registry `hostname --long`:5000 --inputDir $temp_dir/ics_offline"
# - archives ICS manifests
cd $temp_dir
tar cf $air_dir/ics_offline.tar ics_offline
rm -rf ics_offline
podman stop bastion-registry
cd /opt/registry
tar cf ${air_dir}/ics_images.tar data
cd $air_dir
#tar czpvf - *.tar | split -d -b 10G - ics_registry-${ics_version}.tar
tar cf ics_registry-${ics_version}.tar ics_images.tar ics_offline.tar cloudctl-linux-amd64.tar.gz
rm -f ics_offline.tar cloudctl-linux-amd64.tar.gz ics_images.tar
cd $local_directory
# Cleanup gi-temp, portable-registry
podman rm bastion-registry
podman rmi --all
rm -rf /opt/registry
rm -rf $temp_dir
echo "ICS ${ics_version} files prepared - copy $air_dir/ics_registry-${ics_version}.tar to air-gapped bastion machine"
