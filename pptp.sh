#!/bin/bash
# RCAT LAMP Stack for CentOS
# Powered 5ahl.com
# pptp.sh

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script, use sudo $0"
    exit 1
fi

#check if CentOS
if [ ! -e '/etc/redhat-release' ]; then
	echo 'Error: sorry, we currently support CentOS only'
	exit 1
fi

function echoline {
	echo "========================================================================="
}

function repairvpn {
	echo -n "Repairing pptp vpn..."
	rm /dev/ppp
	mknod /dev/ppp c 108 0
	echo " [OK]"
}

function adduser {
	#ask for some information
	while [ "${username}" = "" ]
	do
		read -p "VPN Username: " username
		if [ "${username}" = "" ]; then
			echo "Error: VPN Username Can't be empty!!"
		fi
		ifexists=`cat /etc/ppp/chap-secrets | awk -v U="${username}" '{ if(U==$1) printf $1 }'`
		if [ "$ifexists" != "" ]; then
			echo "Error: ${username} exists."
			username=""
		fi
	done
	while [ "$vpnpwd" = "" ]
	do
		read -p "VPN Password: " vpnpwd
		if [ "$vpnpwd" = "" ]; then
			echo "Error: VPN Password Can't be empty!!"
		fi
	done
	echo "${username} pptpd ${vpnpwd} *" >> /etc/ppp/chap-secrets
	service pptpd restart
	if [ "$?" -ne 0 ]; then
		echo "Error: pptpd restart failed"
		exit 1
	fi
	echo "${username} is added."
}

function deluser {
	#ask for some information
	while [ "${username}" = "" ]
	do
		read -p "VPN Username: " username
		if [ "${username}" = "" ]; then
			echo "Error: VPN Username Can't be empty!!"
		fi
	done
	ifexists=`cat /etc/ppp/chap-secrets | awk -v U="${username}" '{ if(U==$1) printf $1 }'`
	if [ "$ifexists" == "" ]; then
		echo "Error: ${username} does not exist."
	else
		sed -i '/'${username}' pptpd/d' /etc/ppp/chap-secrets
		service pptpd restart
		if [ "$?" -ne 0 ]; then
			echo "Error: pptpd restart failed"
			exit 1
		fi
		echo "${username} is deleted."
	fi
}

function installvpn {
	#ask for some information
	while [ "${username}" = "" ]
	do
		read -p "VPN Username: " username
		if [ "${username}" = "" ]; then
			echo "Error: VPN Username Can't be empty!!"
		fi
	done

	while [ "$vpnpwd" = "" ]
	do
		read -p "VPN Password: " vpnpwd
		if [ "$vpnpwd" = "" ]; then
			echo "Error: VPN Password Can't be empty!!"
		fi
	done

	#get version 
	uname=`uname -i`
	version=`grep -o "[0-9]" /etc/redhat-release | head -n1`

	#update first
	yum -y update
	yum -y install wget

	#install repo
	#yum install epel-release && pptp-release
	if [ "$version" -eq '5' ]; then
		#epel
		wget http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
		wget http://poptop.sourceforge.net/yum/stable/rhel5/pptp-release-current.noarch.rpm
		rpm -Uvh epel-release-5*.rpm
		rpm -Uvh pptp-release-current.noarch.rpm
	elif [ "$version" -eq '6' ]; then
		#epel
		wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
		wget http://poptop.sourceforge.net/yum/stable/rhel6/pptp-release-current.noarch.rpm
		rpm -Uvh epel-release-6*.rpm
		rpm -Uvh pptp-release-current.noarch.rpm
	elif [ "$version" -eq '7' ]; then
		#epel
		wget http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
		rpm -Uvh epel-release-7*.rpm
	fi
	rm -f *.rpm

	#install pptp
	yum install ppp pptpd iptables iptables-services -y

	#configuration
	echo "localip 10.0.0.1" >> /etc/pptpd.conf
	echo "remoteip 10.0.0.2-254" >> /etc/pptpd.conf
	echo "ms-dns 8.8.8.8" >> /etc/ppp/options.pptpd
	echo "ms-dns 8.8.4.4" >> /etc/ppp/options.pptpd

	#create account
	cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets.bak
	echo "${username} pptpd ${vpnpwd} *" > /etc/ppp/chap-secrets
	
	#final fix
	rm -rf /dev/ppp
	mknod /dev/ppp c 108 0
	service pptpd restart
	if [ "$?" -ne 0 ]; then
		echo "Error: pptpd restart failed"
		exit 1
	fi

	#sysctl
	ifexists=`grep net.ipv4.ip_forward /etc/sysctl.conf`
	if [ "$ifexists" == "" ]; then
		echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
	else
		sed -i 's/#net.ipv4.ip_forward/net.ipv4.ip_forward/g' /etc/sysctl.conf
		sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf
	fi
	sysctl -p
	
	#iptables
	if [ "$version" -eq '7' ]; then
		systemctl stop firewalld
		systemctl mask firewalld
		systemctl enable iptables
	fi
	
	if [ -d "/proc/vz" ]; then
		interfaces="venet0"
	else
		interfaces=`ifconfig | grep eth | awk '{print $1}' | head -n 1`
		if [ "$interfaces" = "" ]; then
			interfaces="eth0"
		fi
	fi
	
	iptables -t nat -A POSTROUTING -o $interfaces -j MASQUERADE && iptables-save
	iptables --table nat --append POSTROUTING --out-interface ppp0 -j MASQUERADE
	iptables -I INPUT -s 10.0.0.0/8 -i ppp0 -j ACCEPT
	iptables --append FORWARD --in-interface $interfaces -j ACCEPT
	iptables -A INPUT -p tcp -m tcp --dport 1723 -j ACCEPT
	iptables -A INPUT -p gre -j ACCEPT
	service iptables save
	service iptables restart
	if [ "$?" -ne 0 ]; then
		echo "Error: iptables restart failed"
		exit 1
	fi
	chkconfig pptpd on

	clear
	echo ""
	echo "RCAT PPTP vpn for CentOS"
	echoline
	echo "PPTP VPN installation is finished."
	echo "Username: ${username}"
	echo "Password: ${vpnpwd}"
	echo "For more information, please visit our website http://rcat.xyz/"
	echoline
}

clear
echo ""
echo "RCAT PPTP vpn for CentOS"
echoline
echo "RCAT PPTP vpn is a yum based solution to install PPTP vpn environment"
echo "For more information, please visit our website http://rcat.xyz/"
echo "1. install vpn"
echo "2. repair vpn"
echo "3. add vpn user"
echo "4. delete vpn user"
echoline
read -p "Please input your choice: " choice
case "$choice" in
	1) installvpn
		;;
	2) repairvpn
		;;
	3) adduser
		;;
	4) deluser
		;;
	*) echo "exit"
		;;
esac
