#!/bin/bash

trap display_error EXIT
export MPID=$$

#author: zibi - zszmigiero@gmail.com

#import global variables
. ./scripts/init.globals.sh

function display_error() {
	msg "$1" 9
	trap - EXIT
	kill -s TERM $MPID
}

function msg() {
	case "$2" in
		"0")
			printf "$1"
			;;
		"1")
			printf "$1\n"
			;;
		"2")
			printf "\e[1m>>> $1"
			;;
		"7")
			printf "\e[2mTASK:\e[22m \e[97m$1\n\e[0m"
			;;
		"8")
			printf "\e[2mINFO:\e[22m \e[97m$1\n\e[0m"
			;;
		"9")     
			printf "\e[31m----------------------------------------\n"
			if [ "$1" ]
			then
				printf "Error: $1\n"
			else
				printf "Error in subfunction\n"
			fi
			printf -- "----------------------------------------\n"
			printf "\e[0m"
			;;
		*)
			display_error "msg with incorrect parameter - $2"
			;;
	esac
}

function save_variable() {
        echo "export $1=$2" >> $file
}

function check_bastion_os() {
        if [[ `hostnamectl|grep "Operating System"|awk -F ':' '{print $2}'|awk '{print $1}'` != 'Fedora' ]]
                then
                display_error "Your bastion machine is not Fedora OS - please use the supported Operating System"
        else
                msg "You use `hostnamectl|grep "Operating System"` - tested releases $fedora_supp_releases" 8
        fi
}

function get_network_installation_type() {
        while $(check_input "yn" ${use_air_gap})
        do
                get_input "yn" "Is your environment air-gapped? - " true
                use_air_gap=${input_variable^^}
        done
        if [ $use_air_gap == 'Y' ]
        then
                switch_dnf_sync_off
                save_variable GI_INTERNET_ACCESS "A"
        else
                while $(check_input "dp" ${use_proxy})
                do
                        get_input "dp" "Has your environment direct access to the internet or use HTTP proxy? (\e[4mD\e[0m)irect/(P)roxy: " true
                        use_proxy=${input_variable^^}
                done
                save_variable GI_INTERNET_ACCESS $use_proxy
        fi
}

function switch_dnf_sync_off() {
        if [[ `grep "metadata_timer_sync=" /etc/dnf/dnf.conf|wc -l` -eq 0 ]]
        then
                echo "metadata_timer_sync=0" >> /etc/dnf/dnf.conf
        else
                sed -i 's/.*metadata_timer_sync=.*/metadata_timer_sync=0/' /etc/dnf/dnf.conf
        fi
}

function get_software_selection() {
        while $(check_input "yn" ${gi_install})
        do
                get_input "yn" "Would you like to install Guardium Insights? " false
                gi_install=${input_variable^^}
        done
        save_variable GI_INSTALL_GI $gi_install
        [ $gi_install == 'Y' ] && select_gi_version || select_ics_version
        save_variable GI_ICS $ics_install
        select_ocp_version
        while $(check_input "yn" ${install_ldap})
        do
                get_input "yn" "Would you like to install OpenLDAP? " false
                install_ldap=${input_variable^^}
        done
        save_variable GI_INSTALL_LDAP $install_ldap
}

function display_default_ics() {
	local gi_version
	local i=0
	for gi_version in "${gi_versions[@]}"
	do
		msg "ICS - ${ics_versions[${bundled_in_gi_ics_versions[$i]}]} for GI $gi_version" 8
		i=$((i+1))
	done
}

function select_ics_version() {
	ics_version_selected=""
        while $(check_input "yn" ${ics_install})
        do
                get_input "yn" "Would you like to install Cloud Packs Foundational Services (IBM Common Services)? " false
                ics_install=${input_variable^^}
        done
        if [[ $ics_install == 'Y' ]]
        then
                ics_version_selected=${ics_version_selected:-0}
                while $(check_input "list" ${ics_version_selected} ${#ics_versions[@]})
                do
                        get_input "list" "Select ICS version: " "${ics_versions[@]}"
                        ics_version_selected="$input_variable"
                done
                ics_version_selected=$(($ics_version_selected-1))
                save_variable GI_ICS_VERSION $ics_version_selected
                ics_install='Y'
        else
                ics_install='N'
        fi
}

function select_gi_version() {
	local nd_ics_install
        while $(check_input "list" ${gi_version_selected} ${#gi_versions[@]})
        do
                get_input "list" "Select GI version: " "${gi_versions[@]}"
                gi_version_selected="$input_variable"
        done
        msg "Guardium Insights installation choice assumes installation of bundled version of ICS" 8
        gi_version_selected=$(($gi_version_selected-1))
        save_variable GI_VERSION $gi_version_selected
        ics_version_selected=${bundled_in_gi_ics_versions[$gi_version_selected]}
        ics_install='Y'
	if [[ $use_air_gap == 'N' ]]
	then
		msg "You can overwrite selection of default ICS ${ics_versions[$ics_version_selected]} version" 8
		msg "In this case you must select supported ICS version by GI ${gi_versions[$gi_version_selected]}" 8
		msg "Check documentation before to avoid GI installation problems" 8
		while $(check_input "yn" ${nd_ics_install})
        	do
                	get_input "yn" "Would you like to install non-default Cloud Packs Foundational Services for GI? " true
                	nd_ics_install="${input_variable^^}"
        	done
		[[ "$nd_ics_install" == 'Y' ]] && select_ics_version || save_variable GI_ICS_VERSION $ics_version_selected
	else
		display_default_ics
        	msg "In case of air-gapped installation you must install the bundled ICS version" 8
	fi
}

function select_ocp_version() {
	local i
        if [[ $gi_install == 'Y' ]]
        then
                IFS=':' read -r -a ocp_versions <<< ${ocp_supported_by_gi[$gi_version_selected]}
        elif [[ $ics_install == 'Y' ]]
        then
                IFS=':' read -r -a ocp_versions <<< ${ocp_supported_by_ics[$ics_version_selected]}
        fi
        local new_major_versions=()
        local i=1
        for ocp_version in "${ocp_versions[@]}"
        do
                new_major_versions+=("${ocp_major_versions[$ocp_version]}")
                i=$((i+1))
        done
        ocp_major_version=${ocp_major_version:-0}
        while $(check_input "list" ${ocp_major_version} ${#ocp_versions[@]})
        do
                get_input "list" "Select OCP major version: " "${new_major_versions[@]}"
                ocp_major_version="$input_variable"
        done
        for i in "${!ocp_major_versions[@]}"; do
                [[ "${ocp_major_versions[$i]}" == "${new_major_versions[$(($ocp_major_version-1))]}" ]] && break
        done
        ocp_major_version=$i
        if [[ $use_air_gap == 'N' ]]
        then
                ocp_release_decision=${ocp_release_decision:-Z}
                while $(check_input "es" ${ocp_release_decision})
                do
                        get_input "es" "Would you provide exact version OC to install (E) or use the latest stable [S]? (E)xact/(\e[4mS\e[0m)table: " true
                        ocp_release_decision=${input_variable^^}
                done
        else
                ocp_release_decision='E'
        fi
        if [[ $ocp_release_decision == 'E' ]]
        then
                msg "Insert minor version of OpenShift ${ocp_major_versions[${ocp_major_version}]}.x" 8
                msg "It must be existing version - you can check list of available version using this URL: https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/${ocp_major_versions[${ocp_major_version}]}/latest/" 8
                ocp_release_minor=${ocp_release_minor:-Z}
                while $(check_input "int" ${ocp_release_minor} 0 1000)
                do
                        get_input "txt" "Insert minor version of OCP ${ocp_major_versions[${ocp_major_version}]} to install (must be existing one): " false
                        ocp_release_minor=${input_variable}
                done
                ocp_release="${ocp_major_versions[${ocp_major_version}]}.${ocp_release_minor}"
        else
                ocp_release="${ocp_major_versions[${ocp_major_version}]}.latest"
        fi
        save_variable GI_OCP_RELEASE $ocp_release
}

function display_list () {
        local list=("$@")
        local i=1
        for element in "${list[@]}"
        do
                if [[ $i -eq ${#list[@]} ]]
                then
                        msg "    \e[4m$i\e[24m - $element" 1
                else
                        msg "    $i - $element" 1
                fi
                i=$((i+1))
        done
}

function check_input() {
        case $1 in
                "yn")
                        [[ $2 == 'N' || $2 == 'Y' ]] && echo false || echo true
                        ;;
		"dp")
                        [[ $2 == 'D' || $2 == 'P' ]] && echo false || echo true
                        ;;
		"es")
                        [[ $2 == 'E' || $2 == 'S' ]] && echo false || echo true
                        ;;
		"sto")
                        [[ $2 == 'O' || $2 == 'R' ]] && echo false || echo true
                        ;;
		"list")
                        if [[ $2 == +([[:digit:]]) ]]
                        then
                                [[ $2 -gt 0 && $2 -le $3 ]] && echo false || echo true
                        else
                                echo true
                        fi
                        ;;
		"int")
                        if [[ $2 == +([[:digit:]]) ]]
                        then
                                [[ $2 -ge $3 && $2 -le $4 ]] && echo false || echo true
                        else
                                echo true
                        fi
                        ;;
		"txt")
                        case $3 in
                                "1")
                                        [[ $2 =~ ^[a-zA-Z][a-zA-Z0-9]{1,64}$ ]] && echo false || echo true
                                        ;;
                                "2")
                                        [[ ! -z $2 ]] && echo false || echo true
                                        ;;
                                "3")
                                        if [ -z "$2" ] || $(echo "$2" | egrep -q "[[:space:]]" && echo true || echo false)
                                        then
                                                echo true
                                        else
                                                [[ ${#2} -le $4 ]] && echo false || echo true
                                        fi
                                        ;;
                                "*")
                                        display_error "Error"
                                        ;;
                        esac
                        ;;
		"dir")
			[ -d "$2" ] && echo false || echo true
			;;
		*)
			display_error "Error"
	esac
}

function get_input() {
        unset input_variable
        msg "$2" 2
        case $1 in
                "yn")
                        $3 && msg "(\e[4mN\e[24m)o/(Y)es: " 0 || msg "(N)o/(\e[4mY\e[24m)es: " 0
                        read input_variable
			printf "\e[0m"
                        $3 && input_variable=${input_variable:-N} || input_variable=${input_variable:-Y}
                        ;;
		"dp")
                        read input_variable
                        $3 && input_variable=${input_variable:-D} || input_variable=${input_variable:-P}
                        ;;
		"list")
                        msg "" 1
                        shift
                        shift
                        local list=("$@")
                        display_list $@
                        msg "Your choice: " 0
                        read input_variable
                        input_variable=${input_variable:-${#list[@]}}
                        ;;
		"es")
                        read input_variable
                        $3 && input_variable=${input_variable:-S} || input_variable=${input_variable:-E}
                        ;;
		"txt")
                        read input_variable
                        if $3
                        then
                                [ -z ${input_variable} ] && input_variable="$4"
                        fi
                        ;;
		"pwd")
                        local password=""
                        local password2=""
                        read -s -p "" password
                        echo
			if [ "$password" == "" ] && $3
			then
				curr_password=$password;input_variable=false
			else 
				if [ "$password" == "" ]
				then
					input_variable=true
				else
                        		read -s -p ">>> Insert password again: " password2
                        		echo
					if [ "$password" == "$password2" ]
					then
						curr_password=$password
						input_variable=false
					else
						msg "Please try again" 7
						input_variable=true
					fi
                        	fi
			fi
                        ;;
		"sto")
                        read input_variable
                        $3 && input_variable=${input_variable:-R} || input_variable=${input_variable:-O}
                        ;;
		*)
			display_error "Error"
	esac
}

function prepare_offline_bastion() {
	local curr_password=""
	msg "Bastion preparation to managed installation offline (air-gapped)" 7
	msg "Offline installation requires setup the local image repository on bastion" 8
        while $(check_input "txt" "${repo_admin}" 1)
        do
                if [[ ! -z "$GI_REPO_USER" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_REPO_USER] or insert local registry username: " true "$GI_REPO_USER"
                else
                        get_input "txt" "Insert local registry username (default - repoadmin): " true "repoadmin"
                fi
                        repo_admin="${input_variable}"
        done
        save_variable GI_REPO_USER $repo_admin
	input_variable=true
        while $input_variable
        do
                if [ ! -z "$GI_REPO_USER_PWD" ]
                then
                        get_input "pwd" "Push <ENTER> to accept the previous choice [$GI_REPO_USER_PWD] or insert new password for $repo_admin user: " true "$GI_REPO_USER_PWD"
                else
                        get_input "pwd" "Insert new password for $repo_admin user: " false
                fi
        done
        save_variable GI_REPO_USER_PWD "'$curr_password'"
	msg "Offline installation requires installation archives preparation using preinstall scripts" 8
        msg "Archives must be copied to bastion before installation" 8
        while $(check_input "dir" "${gi_archives}")
        do
                if [[ ! -z "$GI_ARCHIVES_DIR" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_ARCHIVES_DIR] or insert the full path to installation archives: " true "$GI_ARCHIVES_DIR"
                else
                        get_input "txt" "Insert full path to installation archives (default location - $GI_HOME/download): " true "$GI_HOME/download"
                fi
                        gi_archives="${input_variable}"
        done
        save_variable GI_ARCHIVES_DIR "'$gi_archives'"
	process_offline_archives
}

function process_offline_archives() {
	msg "Extracting archives - this process can take several minutes and even hours, be patient ..." 7
	local archive
	local archives=("os-Fedora_release_*" "coreos-registry-${ocp_release}.tar" "olm-registry-${major_ocp_release}*" "additions-registry-*")
	local descs=('Fedora files' "CoreOS ${ocp_release} image" "OLM images for CoreOS ${major_ocp_release}" "Additional software images")
	[ $storage_type == 'R' ] && { archives+=("rook-registry-${rook_version}.tar");descs+=("Rook-Ceph ${rook_version} images");}
	[ $gi_install == 'Y' ] && { archives+=("gi_registry-${gi_versions[$gi_version_selected]}.tar");descs+=("Guardium Insights ${gi_versions[$gi_version_selected]}} images");}
	[[ $ics_install == 'Y' && $gi_install == 'N' ]] && { archives+=("ics_registry-${ics_versions[$ics_version_selected]}}.tar");descs+=("Common Services ${ics_versions[$ics_version_selected]} images");}
	local i=0
	for archive in ${archives[@]}
	do
		if [ -e ${gi_archives}/${archive} ] && [ $(ls ${gi_archives}/${archive}|wc -l) -eq 1 ]
		then
			case $i in
				0)
					msg "Extracting Fedora software packages" 8
					mkdir -p $GI_TEMP/os
					tar -C $GI_TEMP/os -xf ${gi_archives}/$archive kernel.txt ansible/* galaxy/* os-packages/* os-updates/*
					[ $? -ne 0 ] && display_error "Cannot extract content of operating system packages"
					;;
				1)
					msg "Extracting CoreOS images, OCP container images and tools" 8
					mkdir -p /opt/registry $GI_TEMP/coreos
					tar -C $GI_TEMP/coreos -xf $gi_archives/$archive oc-registry.tar openshift-client-linux.tar.gz openshift-install-linux.tar.gz rhcos-live-initramfs.x86_64.img rhcos-live-kernel-x86_64 rhcos-live-rootfs.x86_64.img opm-linux.tar.gz matchbox-v0.9.0-linux-amd64.tar.gz
					tar -C /opt/registry -xf $gi_archives/coreos-registry-${ocp_release}.tar data/*
                                        [ $? -ne 0 ] && display_error "Cannot extract content of CoreOS archive"
                                        ;;
				2)
					msg "Extracting OLM container images" 8
					mkdir -p $GI_TEMP/olm
					tar -C $GI_TEMP/olm -xf $gi_archives/$archive manifests-*
					tar -C /opt/registry -xf $gi_archives/$archive data/*
                                        [ $? -ne 0 ] && display_error "Cannot extract content of OLM archive"
					;;
				3)
					msg "Extracting additional container images, for instance openldap" 8
					mkdir -p $GI_TEMP/adds
					tar -C $GI_TEMP/adds -xf $gi_archives/$archive digests.txt
					tar -C /opt/registry -xf $gi_archives/$archive data/*
					[ $? -ne 0 ] && display_error "Cannot extract content of archive with additional images"
                                        ;;
				4|5|6)
					if [ $archive =~ ^rook.*$ ]
					then
						msg "Extracting Rook-Ceph container images" 8
						mkdir -p $GI_TEMP/rook
						tar -C $GI_TEMP/rook -xf $gi_archives/$archive rook_images_sha
						tar -C /opt/registry -xf $gi_archives/$archive data/*
						[ $? -ne 0 ] && display_error "Cannot extract content of Rook-Ceph archive"
					elif [ $archive =~ ^gi_registry.*$ ]
					then
						msg "Extracting Guardium Insights container images" 8
                                                mkdir -p $GI_TEMP/gi_arch
						tar -C $GI_TEMP/gi_arch -xf $gi_archives/$archive cloudctl-linux-amd64.tar.gz gi_offline/*
                                                tar -C /opt/registry -xf $gi_archives/$archive data/*
                                                [ $? -ne 0 ] && display_error "Cannot extract content of Guardium Insights archive"
					elif [ $archive =~ ^gi_registry.*$ ]
					then
						msg "Extracting Common Services container images" 8
                                                mkdir -p $GI_TEMP/ics_arch
						tar -C $GI_TEMP/ics_arch -xf $gi_archives/$archive cloudctl-linux-amd64.tar.gz ics_offline/*
                                                tar -C /opt/registry -xf $gi_archives/$archive data/*
                                                [ $? -ne 0 ] && display_error "Cannot extract content of Common Services archive"
					else
						display_error "Problem with extraction of archives, unknown archive type"
					fi
					;;
				*)
					display_error "Problem with extraction of archives, check their consitency"
					;;
			esac

		else
			display_error "Cannot find the ${descs[$i]} archive, please copy to archive to ${gi_archives} directory and restart init.sh"
		fi
		i=$(($i+1))
	done
}

function get_software_architecture() {
	msg "Some important architecture decisions and planned software deployment must be made now" 7
        msg "OCP can be installed only on 3 nodes which create control and worker plane" 8
        msg "This kind of architecture has some limitations:" 8
        msg "- You cannot isolate storage on separate nodes" 8
        msg "- You cannot isolate GI and CPFS" 8
        while $(check_input "yn" ${is_master_only})
        do
                get_input "yn" "Is your installation the 3 nodes only? " true
                is_master_only=${input_variable^^}
        done
        save_variable GI_MASTER_ONLY $is_master_only
        msg "Decide what kind of cluster storage option will be implemented:" 8
        msg "- OpenShift Container Storage - commercial rook-ceph branch from RedHat" 8
        msg "- Rook-Ceph - opensource cluster storage option" 8
        while $(check_input "sto" ${storage_type})
        do
                get_input "sto" "Choice the cluster storage type? (O)CS/(\e[4mR\e[0m)ook: " true
                storage_type=${input_variable^^}
        done
        save_variable GI_STORAGE_TYPE $storage_type
        if [[ $storage_type == "O" && $is_master_only == 'N' ]]
        then
                msg "OCS tainting will require minimum 3 additional workers in your cluster to manage cluster storage" 8
                while $(check_input "yn" ${ocs_tainted})
                do
                        get_input "yn" "Should be OCS tainted? " true
                        ocs_tainted=${input_variable^^}
                done
                save_variable GI_OCS_TAINTED $ocs_tainted
        else
                save_variable GI_OCS_TAINTED "N"
        fi
        if [[ $gi_install == "Y" ]]
        then
                while $(check_input "list" ${gi_size_selected} ${#gi_sizes[@]})
                do
                        get_input "list" "Select Guardium Insights deployment template: " "${gi_sizes[@]}"
                        gi_size_selected=$input_variable
                done
                gi_size="${gi_sizes[$((${gi_size_selected} - 1))]}"
                save_variable GI_SIZE_GI $gi_size
        fi
        if [[ $gi_install == "Y" && $is_master_only == 'N' ]]
        then
                msg "DB2 tainting will require additional workers in your cluster to manage Guardium Insights database backend" 8
                while $(check_input "yn" ${db2_tainted})
                do
                        get_input "yn" "Should be DB2 tainted? " true
                        db2_tainted=${input_variable^^}
                done
                save_variable GI_DB2_TAINTED $db2_tainted
        fi
}


#MAIN PART

#prepare_offline_bastion
echo "#gi-runner configuration file" > $file
msg "This script must be executed from gi-runner home directory" 8
msg "Checking OS release" 7
save_variable KUBECONFIG "$GI_HOME/ocp/auth/kubeconfig"
check_bastion_os
msg "Deployment decisions with/without Internet Access" 7
get_network_installation_type
msg "Deployment deicisons about the software and its releases to install" 7
get_software_selection
get_software_architecture
[[ "$use_air_gap" == 'Y' ]] && prepare_offline_bastion
mkdir -p $GI_TEMP

trap - EXIT
