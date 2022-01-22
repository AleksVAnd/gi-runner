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
			printf "\e[34m\e[2mTASK:\e[22m $1\n\e[0m"
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
		"domain")
                        [[ $2 =~  ^([a-zA-Z0-9](([a-zA-Z0-9-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] && echo false || echo true
                        ;;
		"ip")
                        local ip
                        if [[ $2 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
                        then
                                IFS='.' read -r -a ip <<< $2
                                [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
                                [[ $? -eq 0 ]] && echo false || echo true
                        else
                                echo true
                        fi
                        ;;
		"ips")
                        local ip_value
                        IFS=',' read -r -a master_ip_arr <<< $2
                        if [[ ${#master_ip_arr[@]} -eq $3 && $(printf '%s\n' "${master_ip_arr[@]}"|sort|uniq -d|wc -l) -eq 0 ]]
                        then
                                local is_wrong=false
                                for ip_value in "${master_ip_arr[@]}"
                                do
                                        $(check_input "ip" $ip_value) && is_wrong=true
                                done
                                echo $is_wrong
                        else
                                echo true
                        fi
                        ;;
		"mac")
                        [[ $2 =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]] && echo false || echo true
                        ;;
                "macs")
                        local mac_value
                        IFS=',' read -r -a master_mac_arr <<< $2
                        if [[ ${#master_mac_arr[@]} -eq $3 && $(printf '%s\n' "${master_mac_arr[@]}"|sort|uniq -d|wc -l) -eq 0 ]]
                        then
                                local is_wrong=false
                                for mac_value in "${master_mac_arr[@]}"
                                do
                                        $(check_input "mac" $mac_value) && is_wrong=true
                                done
                                echo $is_wrong
                        else
                                echo true
                        fi
                        ;;
		"txt_list")
                        local txt_value
                        local txt_arr
                        IFS=',' read -r -a txt_arr <<< $2
                        if [[ ${#txt_arr[@]} -eq $3 ]]
                        then
                                local is_wrong=false
                                for txt_value in "${txt_arr[@]}"
                                do
                                        [[ "$txt_value" =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,}[a-zA-Z0-9]$ ]] || is_wrong=true
                                done
                                echo $is_wrong
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
		"tz")
                        if [[ "$2" =~ ^[a-zA-Z0-9_+-]{1,}/[a-zA-Z0-9_+-]{1,}$ ]]
                        then
                                timedatectl set-timezone "$2" 2>/dev/null
                                [[ $? -eq 0 ]] && echo false || echo true
                        else
                                echo true
                        fi
                        ;;
                "td")
                        timedatectl set-time "$2" 2>/dev/null
                        [[ $? -eq 0 ]] && echo false || echo true
                        ;;
		"nodes")
                        local element1
                        local element2
                        local i=0
                        local node_arr
                        local selected_arr
                        IFS=',' read -r -a selected_arr <<< "$2"
                        IFS=',' read -r -a node_arr <<< "$3"
                        if [[ $(printf '%s\n' "${selected_arr[@]}"|sort|uniq -d|wc -l) -eq 0 ]]
                        then
                                for element1 in ${selected_arr[@]}; do for element2 in ${node_arr[@]}; do [[ "$element1" == "$element2" ]] && i=$(($i+1));done; done
                                case $5 in
                                        "max")
                                                [ $i -ge $4 ] && echo false || echo true
                                                ;;
                                        "def")
                                                [ $4 -eq $i ] && echo false || echo true
                                                ;;
                                        "*")
                                                display_error "Incorrect nodes size specification"
                                                ;;
                                esac
                        else
                                echo true
                        fi
                        ;;
		*)
			display_error "Error incorrect check_input type"
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
					curr_password="$GI_REPO_USER_PWD"
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
		"int")
                        read input_variable
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
	#process_offline_archives
	software_installation_on_offline
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
					#tar -C $GI_TEMP/os -xf ${gi_archives}/$archive kernel.txt ansible/* galaxy/* os-packages/* os-updates/*
					#[ $? -ne 0 ] && display_error "Cannot extract content of operating system packages"
					;;
				1)
					msg "Extracting CoreOS images, OCP container images and tools" 8
					mkdir -p /opt/registry $GI_TEMP/coreos
					#tar -C $GI_TEMP/coreos -xf $gi_archives/$archive oc-registry.tar openshift-client-linux.tar.gz openshift-install-linux.tar.gz rhcos-live-initramfs.x86_64.img rhcos-live-kernel-x86_64 rhcos-live-rootfs.x86_64.img opm-linux.tar.gz matchbox-v0.9.0-linux-amd64.tar.gz
					#tar -C /opt/registry -xf $gi_archives/coreos-registry-${ocp_release}.tar data/*
                                        #[ $? -ne 0 ] && display_error "Cannot extract content of CoreOS archive"
                                        ;;
				2)
					msg "Extracting OLM container images" 8
					mkdir -p $GI_TEMP/olm
					#tar -C $GI_TEMP/olm -xf $gi_archives/$archive manifests-*
					#tar -C /opt/registry -xf $gi_archives/$archive data/*
                                        #[ $? -ne 0 ] && display_error "Cannot extract content of OLM archive"
					;;
				3)
					msg "Extracting additional container images, for instance openldap" 8
					mkdir -p $GI_TEMP/adds
					tar -C $GI_TEMP/adds -xf $gi_archives/$archive digests.txt
					tar -C /opt/registry -xf $gi_archives/$archive data/*
					[ $? -ne 0 ] && display_error "Cannot extract content of archive with additional images"
                                        ;;
				4|5|6)
					if [ "$archive" == rook-registry-${rook_version}.tar ]
					then
						msg "Extracting Rook-Ceph container images" 8
						mkdir -p $GI_TEMP/rook
						tar -C $GI_TEMP/rook -xf $gi_archives/$archive rook_images_sha
						tar -C /opt/registry -xf $gi_archives/$archive data/*
						[ $? -ne 0 ] && display_error "Cannot extract content of Rook-Ceph archive"
					elif [ "$archive" == gi_registry-${gi_versions[$gi_version_selected]}.tar ]
					then
						msg "Extracting Guardium Insights container images" 8
                                                mkdir -p $GI_TEMP/gi_arch
						tar -C $GI_TEMP/gi_arch -xf $gi_archives/$archive cloudctl-linux-amd64.tar.gz gi_offline/*
                                                tar -C /opt/registry -xf $gi_archives/$archive data/*
                                                [ $? -ne 0 ] && display_error "Cannot extract content of Guardium Insights archive"
					elif [ "$archive" == ics_registry-${ics_versions[$ics_version_selected]}}.tar ]
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

function software_installation_on_offline() {
	local is_updated
	msg "Update and installation of software packaged" 7
	if [[ `uname -r` != `cat $GI_TEMP/os/kernel.txt` ]]
        then
                msg "Kernel of air-gap bastion differs from air-gap file generator!" 8
                msg "In most cases the independent kernel update will lead to problems with system libraries" 8
		while $(check_input "yn" ${is_updated})
                do
                        get_input "yn" "Have you updated system before, would you like to continue? " true
                        is_updated=${input_variable^^}
                done
                if [ $is_updated != 'N' ]
                then
                        display_error "Upload air-gap files corresponding to bastion kernel or generate files for bastion environment"
                fi
        fi
        msg "Installing OS updates" 7
        dnf -qy --disablerepo=* localinstall ${GI_TEMP}/os/os-updates/*rpm --allowerasing
        msg "Installing OS packages" 7
        dnf -qy --disablerepo=* localinstall ${GI_TEMP}/os/os-packages/*rpm --allowerasing
        msg "Installing Ansible and python modules" 7
        cd ${GI_TEMP}/os/ansible
        pip3 install passlib-* --no-index --find-links '.' > /dev/null 2>&1
        pip3 install dnspython-* --no-index --find-links '.' > /dev/null 2>&1
        cd $GI_TEMP/os/galaxy
        ansible-galaxy collection install community-general-3.3.2.tar.gz
        cd $GI_HOME
        mkdir -p /etc/ansible
        echo -e "[bastion]\n127.0.0.1 ansible_connection=local" > /etc/ansible/hosts
        msg "OS software update and installation successfully finished" 8
}

function software_installation_on_online() {
	msg "Update and installation of software packaged" 7
	msg "Installing OS updates" 7
        dnf -qy update
        msg "Installing OS packages"
        local soft=("tar" "ansible" "haproxy" "openldap" "perl" "podman-docker" "ipxe-bootimgs" "chrony" "dnsmasq" "unzip" "wget" "httpd-tools" "policycoreutils-python-utils" "python3-ldap" "openldap-servers" "openldap-clients" "pip" "skopeo")
        for package in "${soft[@]}"
        do
                msg "- installing $package ..." 8
                dnf -qy install $package &>/dev/null
                [[ $? -ne 0 ]] && display_error "Cannot install $package"
        done
        msg "Installing Python packages" 7
        local python_soft=("passlib" "dnspython" "beautifulsoup4")
        for package in "${python_soft[@]}"
        do
                msg "- installing $package ..." 8
                [[ $use_proxy == 'D' ]] && pip3 install "$package" || pip3 install "$package" --proxy http://$proxy_ip:$proxy_port
                [[ $? -ne 0 ]] && display_error "Cannot install python package $package"
        done
        msg "Configuring Ansible" 7
        mkdir -p /etc/ansible
        [[ $use_proxy == 'P' ]] && echo -e "[bastion]\n127.0.0.1 \"http_proxy=http://$proxy_ip:$proxy_port\" https_proxy=\"http://$proxy_ip:$proxy_port\" ansible_connection=local" > /etc/ansible/hosts || echo -e "[bastion]\n127.0.0.1 ansible_connection=local" > /etc/ansible/hosts
        echo "pullSecret: '$rhn_secret'" > ${GI_TEMP}/os/pull_secret.tmp
}

function get_ocp_domain() {
	msg "Set cluster domain name" 7
        msg "Insert the OCP cluster domain name - it is local cluster, so it doesn't have to be registered as public one" 8
        while $(check_input "domain" ${ocp_domain})
        do
                if [[ ! -z "$GI_DOMAIN" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_DOMAIN] or insert domain name: " true "$GI_DOMAIN"
                else
                        get_input "txt" "Insert domain name: " false
                fi
                ocp_domain=${input_variable}
        done
        save_variable GI_DOMAIN $ocp_domain
}

function get_bastion_info() {
	msg "Collecting data about bastion" 7
        msg "Provide IP address of network interface on bastion which is connected to this same subnet,vlan where the OCP nodes are located" 8
        while $(check_input "ip" ${bastion_ip})
        do
                if [[ ! -z "$GI_BASTION_IP" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_BASTION_IP] or insert bastion IP: " true "$GI_BASTION_IP"
                else
                        get_input "txt" "Insert bastion IP: " false
                fi
                bastion_ip=${input_variable}
        done
        save_variable GI_BASTION_IP $bastion_ip
        msg "Provide the hostname used to resolve bastion name by local DNS which will be set up" 8
        while $(check_input "txt" ${bastion_name} 1)
        do
                if [[ ! -z "$GI_BASTION_NAME" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_BASTION_NAME] or insert bastion name: " true "$GI_BASTION_NAME"
                else
                        get_input "txt" "Insert bastion name: " false
                fi
                bastion_name=${input_variable}
        done
        save_variable GI_BASTION_NAME $bastion_name
        msg "Provide the IP gateway of subnet where cluster node are located" 8
        while $(check_input "ip" ${subnet_gateway})
        do
                if [[ ! -z "$GI_GATEWAY" ]]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_GATEWAY] or insert IP address of default gateway: " true "$GI_GATEWAY"
                else
                        get_input "txt" "Insert IP address of default gateway: " false
                fi
                subnet_gateway=${input_variable}
        done
        save_variable GI_GATEWAY $subnet_gateway
}

function get_nodes_info() {
        local temp_ip
        local temp_mac
        local temp_name
        case $2 in
                "ocs")
                        local pl_names=("addresses" "names" "IP's" "hosts")
                        local node_type="OCS nodes"
                        local global_var_ip=$GI_OCS_IP
                        local global_var_mac=$GI_OCS_MAC_ADDRESS
                        local global_var_name=$GI_OCS_NAME
                        ;;
                "boot")
                        local pl_names=("address" "name" "IP" "host")
                        local node_type="bootstrap node"
                        local global_var_ip=$GI_BOOTSTRAP_IP
                        local global_var_mac=$GI_BOOTSTRAP_MAC_ADDRESS
                        local global_var_name=$GI_BOOTSTRAP_NAME
                        ;;
                "mst")
                        local pl_names=("addresses" "names" "IP's" "hosts")
                        local node_type="master nodes"
                        local global_var_ip=$GI_MASTER_IP
                        local global_var_mac=$GI_MASTER_MAC_ADDRESS
                        local global_var_name=$GI_MASTER_NAME
                        ;;
                "wrk")
                        local pl_names=("addresses" "names" "IP's" "hosts")
                        local node_type="worker nodes"
                        local global_var_ip=$GI_WORKER_IP
                        local global_var_mac=$GI_WORKER_MAC_ADDRESS
                        local global_var_name=$GI_WORKER_NAME
                        ;;
                "*")
                        exit 1
	esac
        msg "Insert $1 ${pl_names[2]} ${pl_names[0]} of $node_type, should be located in subnet with gateway - $subnet_gateway" 8
        while $(check_input "ips" ${temp_ip} $1)
        do
                if [ ! -z "$global_var_ip" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$global_var_ip] or insert $node_type ${pl_names[2]}: " true "$global_var_ip"
                else
                        get_input "txt" "Insert $node_type IP: " false
                fi
                temp_ip=${input_variable}
        done
        msg "Insert $1 MAC ${pl_names[0]} of $node_type" 8
        while $(check_input "macs" ${temp_mac} $1)
        do
                if [ ! -z "$global_var_mac" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$global_var_mac] or insert $node_type MAC ${pl_names[0]}: " true "$global_var_mac"
                else
                        get_input "txt" "Insert $node_type MAC ${pl_names[0]}: " false
                fi
                temp_mac=${input_variable}
        done
        msg "Insert $1 ${pl_names[3]} ${pl_names[1]} of $node_type" 8
        while $(check_input "txt_list" ${temp_name} $1)
        do
                if [ ! -z "$global_var_name" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$global_var_name] or insert $node_type ${pl_names[1]}: " true "$global_var_name"
                else
                        get_input "txt" "Insert bootstrap ${pl_names[1]}: " false
                fi
                temp_name=${input_variable}
        done
	case $2 in
                "ocs")
                        ocs_ip=$temp_ip
                        save_variable GI_OCS_IP $temp_ip
                        save_variable GI_OCS_MAC_ADDRESS $temp_mac
                        save_variable GI_OCS_NAME $temp_name
                        ;;
                "boot")
                        boot_ip=$temp_ip
                        save_variable GI_BOOTSTRAP_IP $temp_ip
                        save_variable GI_BOOTSTRAP_MAC_ADDRESS $temp_mac
                        save_variable GI_BOOTSTRAP_NAME $temp_name
                        ;;
                "mst")
                        master_ip=$temp_ip
                        save_variable GI_MASTER_IP $temp_ip
                        save_variable GI_MASTER_MAC_ADDRESS $temp_mac
                        save_variable GI_MASTER_NAME $temp_name
                        ;;
                "wrk")
                        worker_ip=$temp_ip
                        worker_name=$temp_name
                        save_variable GI_WORKER_IP $temp_ip
                        save_variable GI_WORKER_MAC_ADDRESS $temp_mac
                        save_variable GI_WORKER_NAME $temp_name
                        ;;
                "*")
                        display_error "Incorrect parameters get_node function"
        esac
}

function get_worker_nodes() {
        local worker_number=3
        local inserted_worker_number
        if [[ $is_master_only == 'N' ]]
        then
		msg "Collecting workers data" 7
                if [[ $storage_type == 'O' && $ocs_tainted == 'Y' ]]
                then
			msg "Collecting OCS dedicated nodes data because OCS tainting has been chosen (IP and MAC addresses, node names), values inserted as comma separated list without spaces" 7
                        get_nodes_info 3 "ocs"
                fi
                if [ $db2_tainted == 'Y' ]
                then
                        [ $gi_size == "values-small" ] && worker_number=$(($worker_number+2)) || worker_number=$(($worker_number+1))
                fi
                msg "Your cluster architecture decisions require to have minimum $worker_number additional workers" 8
                while $(check_input "int" $inserted_worker_number $worker_number 50)
                do
                        get_input "int" "How many additional workers would you like to add to cluster?: " false
                        inserted_worker_number=${input_variable}
                done
		msg "Collecting workers nodes data (IP and MAC addresses, node names), values inserted as comma separated list without spaces" 7
                get_nodes_info $inserted_worker_number "wrk"
        fi
}

function set_bastion_ntpd_client() {
	msg "Set NTPD configuration" 7
	sed -i "s/^pool .*/pool $1 iburst/g" /etc/chrony.conf
        systemctl enable chronyd
        systemctl restart chronyd
}

function get_set_services() {
        local iz_tz_ok
        local is_td_ok
        local ntpd_server
        local tzone
        local tida
        msg "Some additional questions allow to configure supporting services in your environment" 8
	msg "Time settings" 7
        msg "It is recommended to use existing NTPD server in the local intranet but you can also decide to setup bastion as a new one" 8
        while $(check_input "yn" $install_ntpd false)
        do
                get_input "yn" "Would you like setup NTP server on bastion?: " false
                install_ntpd=${input_variable^^}
        done
        if [[ $install_ntpd == 'N' ]]
        then
                timedatectl set-ntp true
                while $(check_input "ip" ${ntp_server})
                do
                        if [ ! -z "$GI_NTP_SRV" ]
                        then
                                get_input "txt" "Push <ENTER> to accept the previous choice [$GI_NTP_SRV] or insert remote NTP server IP address: " true "$GI_NTP_SRV"
                        else
                                get_input "txt" "Insert remote NTP server IP address: " false
                        fi
                        ntpd_server=${input_variable}
                done
                save_variable GI_NTP_SRV $ntpd_server
	else
		ntpd_server=$bastion_ip
		timedatectl set-ntp false
        fi
        set_bastion_ntpd_client "$ntpd_server"
        msg "Ensure that TZ and corresponding time is set correctly" 7
        while $(check_input "yn" $is_tz_ok)
        do
                get_input "yn" "Your Timezone on bastion is set to `timedatectl show|grep Timezone|awk -F '=' '{ print $2 }'`, is it correct one?: " false
                is_tz_ok=${input_variable^^}
        done
        if [[ $is_tz_ok == 'N' ]]
        then
                while "tz" $(check_input ${tzone})
                do
                        get_input "txt" "Insert your Timezone in Linux format (i.e. Europe/Berlin): " false
                        tzone=${input_variable}
                done
        fi
        if [[ $install_ntpd == 'Y' ]]
        then
                save_variable GI_NTP_SRV $bastion_ip
                msg "Ensure that date and time are set correctly" 7
                while $(check_input "yn" $is_td_ok false)
                do
                        get_input "yn" "Current local time is `date`, is it correct one?: " false
                        is_td_ok=${input_variable^^}
                done
                if [[ $is_td_ok == 'N' ]]
                then
                        while $(check_input "td" "${tida}")
                        do
                                get_input "txt" "Insert correct date and time in format \"2012-10-30 18:17:16\": " false
                                tida="${input_variable}"
                        done
                fi
	fi
	msg "DNS settings" 7
        msg "Provide the DNS which will able to resolve intranet and internet names" 8
        msg "In case of air-gapped installation you can point bastion itself but cluster will not able to resolve intranet names, in this case you must later update manually dnsmasq.conf settings" 8
        while $(check_input "ip" ${dns_fw})
        do
                if [ ! -z "$GI_DNS_FORWARDER" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_DNS_FORWARDER] or insert DNS server IP address: " true "$GI_DNS_FORWARDER"
                else
                        get_input "txt" "Insert DNS IP address: " false
                fi
                dns_fw=${input_variable}
        done
        save_variable GI_DNS_FORWARDER $dns_fw
        IFS=',' read -r -a all_ips <<< `echo $boot_ip","$master_ip","$ocs_ip",$worker_ip"|tr -s ',,' ','|sed 's/,[[:blank:]]*$//g'`
        save_variable GI_DHCP_RANGE_START `printf '%s\n' "${all_ips[@]}"|sort -t . -k 3,3n -k 4,4n|head -n1`
        save_variable GI_DHCP_RANGE_STOP `printf '%s\n' "${all_ips[@]}"|sort -t . -k 3,3n -k 4,4n|tail -n1`
}

function get_hardware_info() {
	msg "Collecting hardware information" 7
        msg "Automatic CoreOS and storage deployment requires information about NIC and HDD devices" 8
        msg "There is assumption that all cluster nodes including bootstrap machine use this isame HW specification" 8
        msg "The Network Interface Card (NIC) device specification must provide the one of interfaces attached to each cluster node and connected to cluster subnet" 8
        msg "In most cases the first NIC attached to machine will have on Fedora and RedHat the name \"ens192\"" 8
        while $(check_input "txt" "${machine_nic}" 2)
        do
                if [ ! -z "$GI_NETWORK_INTERFACE" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_NETWORK_INTERFACE] or insert NIC specification: " true "$GI_NETWORK_INTERFACE"
                else
                        get_input "txt" "Insert NIC specification: " false
                fi
                machine_nic="${input_variable}"
        done
        save_variable GI_NETWORK_INTERFACE "$machine_nic"
        msg "There is assumption that all cluster machines use this device specification for boot disk" 8
        msg "In most cases the first boot disk will have specification \"sda\" or \"nvmne0\"" 8
        msg "The inserted value refers to root path located in /dev" 8
        msg "It means that value sda refers to /dev/sda" 8
        while $(check_input "txt" "${machine_disk}" 2)
        do
                if [ ! -z "$GI_BOOT_DEVICE" ]
                then
                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_BOOT_DEVICE] or insert boot disk specification: " true "$GI_BOOT_DEVICE"
                else
                        get_input "txt" "Insert boot disk specification: " false
                fi
                machine_disk="${input_variable}"
        done
        save_variable GI_BOOT_DEVICE "$machine_disk"
}

function get_service_assignment() {
	msg "Architecture decisions about service location on cluster nodes" 7
        local selected_arr
        local node_arr
	local element
	local rook_on_list
        if [[ $gi_install == 'Y' ]]
        then
                [[ $gi_size == 'values-small' ]] && db2_nodes_size=2 || db2_nodes_size=1
		if [[ $db2_tainted == 'Y' ]]
		then
                	msg "You decided that DB2 will be installed on dedicated nodes" 8
                	msg "These nodes should not be used as storage cluster nodes" 8
		fi
                msg "Available worker nodes: $worker_name" true
                while $(check_input "nodes" $db2_nodes $worker_name $db2_nodes_size "def")
                do
                        if [ ! -z "$GI_DB2_NODES" ]
                        then
                                get_input "txt" "Push <ENTER> to accept the previous choice [$GI_DB2_NODES] or specify $db2_nodes_size node/nodes (comma separated, without spaces)?: " true "$GI_DB2_NODES"
                        else
                                get_input "txt" "Specify $db2_nodes_size node/nodes (comma separated, without spaces)?: " false
                        fi
                        db2_nodes=${input_variable}
                done
                save_variable GI_DB2_NODES "$db2_nodes"
                IFS=',' read -r -a selected_arr <<< "$db2_nodes"
                IFS=',' read -r -a node_arr <<< "$worker_name"
                if [[ "$db2_tainted" == 'N' ]]
                then
                        worker_wo_db2_name=$worker_name
		else
                	for element in ${selected_arr[@]};do node_arr=("${node_arr[@]/$element}");done
                	worker_wo_db2_name=`echo ${node_arr[*]}|tr ' ' ','`
                	workers_for_gi_selection=$worker_wo_db2_name
                fi
        fi
        if [[ $storage_type == "R" && $is_master_only == "N" && ${#node_arr[@]} -gt 3 ]]
        then
                msg "You specified Rook-Ceph as cluster storage" 8
                msg "You can force to deploy it on strictly defined node list" 8
                msg "Only disks from specified nodes will be configured as cluster storage" 8
                while $(check_input "yn" $rook_on_list false)
                do
                        get_input "yn" "Would you like to install Rook-Ceph on strictly specified nodes?: " true
                        rook_on_list=${input_variable^^}
                done
                if [ "$rook_on_list" == 'Y' ]
                then
                        msg "Available worker nodes: $worker_wo_db2_name" 8
                        while $(check_input "nodes" $rook_nodes $worker_wo_db2_name 3 "def")
                        do
                                if [ ! -z "$GI_ROOK_NODES" ]
                                then
                                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_ROOK_NODES] or specify 3 nodes (comma separated, without spaces)?: " true "$GI_ROOK_NODES"
                                else
                                        get_input "txt" "Specify 3 nodes (comma separated, without spaces)?: " false
                                fi
                                rook_nodes=${input_variable}
                        done
                fi
        fi
	save_variable GI_ROOK_NODES "$rook_nodes"
        if [[ $ics_install == "Y" && $is_master_only == "N" && ${#node_arr[@]} -gt 3 ]]
        then
                msg "You can force to deploy ICS on strictly defined node list" 8
                while $(check_input "yn" $ics_on_list false)
                do
                        get_input "yn" "Would you like to install ICS on strictly specified nodes?: " true
                        ics_on_list=${input_variable^^}
                done
                if [ "$ics_on_list" == 'Y' ]
                then
                        msg "Available worker nodes: $worker_wo_db2_name" 8
                        while $(check_input $ics_nodes "nodes" $worker_wo_db2_name 3 "def")
                        do
                                if [ ! -z "$GI_ICS_NODES" ]
                                then
                                        get_input "txt" "Push <ENTER> to accept the previous choice [$GI_ICS_NODES] or specify 3 nodes (comma separated, without spaces)?: " true "$GI_ICS_NODES"
                                else
                                        get_input "txt" "Specify 3 nodes (comma separated, without spaces)?: " false
                                fi
                                ics_nodes=${input_variable}
                        done
                fi
        fi
        save_variable GI_ICS_NODES "$ics_nodes"
        if [ "$gi_install" == 'Y' ]
        then
                IFS=',' read -r -a worker_arr <<< "$worker_name"
                if [[ ( $db2_tainted == 'Y' && ${#node_arr[@]} -gt 3 ) ]] || [[ ( $db2_tainted == 'N' && "$gi_size" == "values-small" && ${#worker_arr[@]} -gt 5 ) ]] || [[ ( $db2_tainted == 'N' && "$gi_size" == "values-dev" && ${#worker_arr[@]} -gt 4 ) ]]
                then
                        msg "You can force to deploy GI on strictly defined node list" 8
                        while $(check_input "yn" $gi_on_list false)
                        do
                                get_input "yn" "Would you like to install GI on strictly specified nodes?: " true
                                gi_on_list=${input_variable^^}
                        done
                fi
                if [[ $db2_tainted == 'Y' && ${#node_arr[@]} -gt 3 ]]
                then
                        no_nodes_2_select=3
                else
                        [ "$gi_size" == "values-small" ] && no_nodes_2_select=1 || no_nodes_2_select=2
                fi
                if [ "$gi_on_list" == 'Y' ]
                then
                        if [ ! -z "$GI_GI_NODES" ]
                        then
                                local previous_node_ar
                                local current_selection
                                IFS=',' read -r -a previous_node_arr <<< "$GI_GI_NODES"
                                IFS=',' read -r -a db2_node_arr <<< "$db2_nodes"
                                for element in ${db2_node_arr[@]};do previous_node_arr=("${previous_node_arr[@]/$element}");done
                                current_selection=`echo ${previous_node_arr[*]}|tr ' ' ','`
                        fi
                        msg "DB2 node/nodes: $db2_nodes are already on the list included, additionally you must select minimum $no_nodes_2_select node/nodes from the list below:" 8
                        msg "Available worker nodes: $workers_for_gi_selection" 8
                        while $(check_input "nodes" $gi_nodes $workers_for_gi_selection $no_nodes_2_select "max")
                        do
                                if [ ! -z "$GI_GI_NODES" ]
                                then
                                        get_input "txt" "Push <ENTER> to accept the previous choice [$current_selection] or specify minimum $no_nodes_2_select node/nodes (comma separated, without spaces)?: " true "$current_selection"
                                else
                                        get_input "txt" "Specify minimum $no_nodes_2_select node/nodes (comma separated, without spaces)?: " false
                                fi
                                gi_nodes=${input_variable}
                        done
                fi
        fi
	save_variable GI_GI_NODES "${db2_nodes},$gi_nodes"
}
#MAIN PART

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
mkdir -p $GI_TEMP
[[ "$use_air_gap" == 'Y' ]] && prepare_offline_bastion
msg "Installing tools for init.sh" 7
[[ "$use_air_gap" == 'N' ]] && { dnf -qy install jq;[[ $? -ne 0 ]] && display_error "Cannot install jq"; }
get_ocp_domain
get_bastion_info
msg "Collecting data about bootstrap node (IP and MAC addres, name)" 7
get_nodes_info 1 "boot"
msg "Collecting Control Plane nodes data (IP and MAC addres, name), values must beinserted as comma separated list without spaces" 7
get_nodes_info 3 "mst"
get_worker_nodes
#software_installation_on_online
get_set_services
get_hardware_info
get_service_assignment
trap - EXIT
