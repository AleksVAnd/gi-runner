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
			printf "Error: $1\n"
			printf -- "----------------------------------------\n"
			printf "\e[0m"
			;;
		*)
			error_msg "msg with incorrect parameter - $2"
			exit 1
			;;
	esac
}

function save_variable() {
        echo "export $1=$2" >> $file
}

function check_bastion_os() {
        if [[ `hostnamectl|grep "Operating System"|awk -F ':' '{print $2}'|awk '{print $1}'` != 'Fedora' ]]
                then
                error_msg="Your bastion machine is not Fedora OS - please use the supported Operating System"
		exit 1
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

function check_input() {
        case $1 in
                "yn")
                        [[ $2 == 'N' || $2 == 'Y' ]] && echo false || echo true
                        ;;
		*)
			error_msg="Unknown type of check_input"
			display_error "aaaaa"
			;;
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
		*)
			error_msg="Unknown type of get_input"
			echo "1"
			display_error
			;;
	esac
}


#MAIN PART

echo "#gi-runner configuration file" > $file
msg "This script must be executed from gi-runner home directory" 8
msg "Checking OS release" 7
save_variable KUBECONFIG "$GI_HOME/ocp/auth/kubeconfig"
check_bastion_os
get_network_installation_type



trap - EXIT
