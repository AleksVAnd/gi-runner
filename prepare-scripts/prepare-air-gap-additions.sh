#!/bin/bash

function check_exit_code() {
        if [[ $1 -ne 0 ]]
        then
                echo $2
                echo "Please check the reason of problem and restart script"
                exit 1
        else
                echo "OK"
        fi
}

echo "Setting environment"
registry_version=2.7.1
local_directory=`pwd`
host_fqdn=$(hostname --long)
temp_dir=$local_directory/gi-temp
air_dir=$local_directory/air-gap
# Creates temporary directory
mkdir -p $air_dir
dnf -qy install python3 podman wget
check_exit_code $? "Cannot install required OS packages"
echo "Setup mirror image registry ..."
# - cleanup repository if exists
podman stop bastion-registry
podman container prune <<< 'Y'
rm -rf /opt/registry
# - Pulls image of portable registry and save it 
podman pull docker.io/library/registry:${registry_version}
check_exit_code $? "Cannot download image registry"
# - Prepares portable registry directory structure
mkdir -p /opt/registry/{auth,certs,data}
# - Creates SSL cert for portable registry (only for mirroring, new one will be created in disconnected env)
openssl req -newkey rsa:4096 -nodes -sha256 -keyout /opt/registry/certs/bastion.repo.pem -x509 -days 365 -out /opt/registry/certs/bastion.repo.crt -subj "/C=PL/ST=Miedzyrzecz/L=/O=Test /OU=Test/CN=`hostname --long`" -addext "subjectAltName = DNS:${host_fqdn}"
check_exit_code $? "Cannot create certificate for temporary image registry"
cp /opt/registry/certs/bastion.repo.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
# - Creates user to get access to portable repository
dnf -qy install httpd-tools
check_exit_code $? "Cannot install httpd-tools"
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
echo "Starting mirror image registry ..."
podman run -d --name bastion-registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" -e "REGISTRY_HTTP_SECRET=ALongRandomSecretForRegistry" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/bastion.repo.crt -e REGISTRY_HTTP_TLS_KEY=/certs/bastion.repo.pem docker.io/library/registry:${registry_version}
check_exit_code $? "Cannot start temporary image registry"
# Packs together centos updates, packages, python libraries and portable image
echo "Mirroring openldap container"
images="docker.io/bitnami/openldap:latest"
for image in $images
do
	echo $image
        podman pull $image
	check_exit_code $? "Cannot pull image $image"
        tag=`echo "$image" | awk -F '/' '{print $NF}'`
        echo "TAG: $tag"
	podman push --creds admin:guardium $image ${host_fqdn}:5000/adds/$tag
	podman rmi $image
done
echo "Extracting image digests ..."
echo "openldap:latest,"podman inspect ${host_fqdn}:5000/adds/openldap:latest|jq .[0].Digest|tr -d '"' >> ${air_dir}/digests.txt
exit 0
echo "Archiving mirrored registry ..."
podman stop bastion-registry
cd /opt/registry
tar cf ${air_dir}/additions-registry-`date +%Y-%m-%d`.tar data
cd ${air_dir}
tar -rf ${air_dir}/additions-registry-`date +%Y-%m-%d`.tar digest.txt
rm -f digests.txt
podman rm bastion-registry
podman rmi --all
rm -rf /opt/registry
rm -rf $temp_dir
echo "Images with additonal services prepared - copy file ${air_dir}/addition-registry-`date +%Y-%m-%d`.tar to air-gapped bastion machine"
