#!/bin/bash

#====================================================
#	System Request:Debian 7+/Ubuntu 14.04+/Centos 6+
#	Author:	worms
#	Dscription: SSR server for manyuser (only)
#	Version: B1
#====================================================

sh_ver="B1"
libsodium-version="libsodium-stable"
libsodium_folder="/usr/local/libsodium"
shadowsocks_install_folder="/usr/local"
supervisor_dir="/etc/supervisor"
suerpvisor_conf_dir="${supervisor_dir}/conf.d"
shadowsocks_folder="${shadowsocks_install_folder}/shadowsocksr"
config="${shadowsocks_folder}/config.json"
debian_sourcelist="/etc/apt/source.list"

#fonts color
Green="\033[32m" 
Red="\033[31m" 
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"


#notification information
Info="${Green}[Info]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[Error]${Font}"
Notification="${Yellow}[Notification]${Font}"

source /etc/os-release &>/dev/null

check_system(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前账号非ROOT(或没有ROOT权限)" && exit 1
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${Font} "
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${Font} "
        INS="apt-get"
    elif [[ "${ID}" == "ubuntu" && `echo "${VERSION_ID}" | cut -d '.' -f1` -ge 16 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${Font} "
        INS="apt-get"
	elif [[ `rpm -q centos-release |cut -d - -f1` == "centos" && `rpm -q centos-release |cut -d - -f3` == 6 ]];then
		echo -e "${OK} ${GreenBG} 当前系统为 Centos 6 ${Font} "
        INS="yum"
		ID="centos"
		VERSION_ID="6"
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font} "
        exit 1
    fi
}
basic_installation(){
	if [[ ${ID} == "centos" ]]; then
		${INS} install tar wget gcc git epel-release -y
	else
		sed -i '/^deb cdrom/'d /etc/apt/sources.list
		${INS} update
		${INS} install tar wget -y
	fi
}
# 设置 防火墙规则
Add_iptables(){
	iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
	iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
	ip6tables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
	ip6tables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
}
Del_iptables(){
	iptables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
	iptables -D INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
	ip6tables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
	ip6tables -D INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
}
Save_iptables(){
	if [[ ${release} == "centos" ]]; then
		service iptables save
		service ip6tables save
	else
		iptables-save > /etc/iptables.up.rules
		ip6tables-save > /etc/ip6tables.up.rules
	fi
}
dependency_installation(){
		${INS} -y install python-setuptools  && easy_install pip
		if [[ $? -ne 0 ]]; then
			if [[ ${ID} == "centos" ]];then
				echo -e "${OK} ${GreenBG} 尝试 yum 安装 python-pip ${Font}"
				sleep 2
				yum -y install python-pip 
			else
				echo -e "${OK} ${GreenBG} 尝试 apt 安装 python-pip ${Font}"
				sleep 2
				apt-get install python-pip -y
			fi
			if [[ $? -eq 0 ]]; then
				echo -e "${OK} ${GreenBG} pip 安装完成 ${Font}"
				sleep 1
				else
				echo -e "${Error} ${RedBG} pip 安装失败 ${Font}"
				exit 1
			fi
		fi
}
development_tools_installation(){
	if [[ ${ID} == "centos" ]]; then
		${INS} groupinstall "Development Tools" -y
		if [[ $? -ne 0 ]]; then
			echo -e "${Error} ${RedBG} Development Tools 安装失败 ${Font}"
			exit 1
		fi
	else
		${INS} install build-essential -y
		if [[ $? -ne 0 ]]; then
			echo -e "${Error} ${RedBG} build-essential 安装失败 ${Font}"
			exit 1
		fi
	fi
	
}
libsodium_installation(){
	echo -e "${Info} 正在下载 libsodium"
	wget https://raw.githubusercontent.com/pandoraes/shadowsocksr-manyuser/master/libsodium/${libsodium-version}.tar.gz
	if [[ ! -f ${libsodium-version}.tar.gz ]]; then
		echo -e "${Error} ${RedBG} ${libsodium-version} 下载失败 ${Font}"
		exit 1
	fi
	tar xf ${libsodium-version}.tar.gz && rm -rf ${libsodium-version}.tar.gz && cd ${libsodium-version}
	./configure --prefix=${libsodium_folder} && make -j2 && make install
	if [[ $? -ne 0 ]]; then 
		echo -e "${Error} ${RedBG} ${libsodium-version} install FAIL ${Font}"
		exit 1
	fi
	echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
	ldconfig
}
SSR_dependency_installation(){
	if [[ ${ID} == "centos" ]]; then
		cd ${shadowsocks_folder}
		${INS} install python-devel libffi-devel openssl-devel -y
		pip install -r requirements.txt
		pip install requests		
	else
		pip install cymysql
		pip install requests
	fi
}
supervisor_installation(){
	if [[ ! -d ${shadowsocks_folder} ]]; then
		read -p "请输入shadowsocks所在目录绝对路径（eg：/usr/local/shadowsocksr）" shadowsocks_folder
	fi
	if [[ ${ID} == "centos" ]];then
		${INS} -y install supervisor
	else
		apt-get install supervisor -y
	fi
	if [[ $? -ne 0 ]]; then 
		echo -e "${Error} ${RedBG} supervisor 安装失败 ${Font}"
		exit 1
	else
		echo -e "${OK} ${GreenBG} supervisor 安装成功 ${Font}"
		sleep 1
	fi
	

}
supervisor_conf_modify_debian(){
	cat>${suerpvisor_conf_dir}/shadowsocks.conf<<EOF
[program:shadowsocks]
command = python ${shadowsocks_folder}/server.py
stdout_logfile = /var/log/ssmu.log
stderr_logfile = /var/log/ssmu.log
user = root
autostart = true
autorestart = true
EOF

	echo -e "${OK} ${GreenBG} supervisor 配置导入成功 ${Font}"
	sleep 1
}
supervisor_conf_modify_ubuntu(){
	cat>${suerpvisor_conf_dir}/shadowsocks.conf<<EOF
[program:shadowsocks]
command = python ${shadowsocks_folder}/server.py
stdout_logfile = /var/log/ssmu.log
stderr_logfile = /var/log/ssmu.log
user = root
autostart = true
autorestart = true
EOF

	echo -e "${OK} ${GreenBG} supervisor 配置导入成功 ${Font}"
	sleep 1
}
supervisor_conf_modify_centos(){
	cat>>/etc/supervisord.conf<<EOF
[program:shadowsocks]
command = python ${shadowsocks_folder}/server.py
stdout_logfile = /var/log/ssmu.log
stderr_logfile = /var/log/ssmu.log
user = root
autostart = true
autorestart = true
EOF

	echo -e "${OK} ${GreenBG} supervisor 配置导入成功 ${Font}"
	sleep 1
}

iptables_OFF(){
	systemctl disable firewalld &>/dev/null
	systemctl disable iptables &>/dev/null
	chkconfig iptables off &>/dev/null
	iptables -F	&>/dev/null
}

check_install_ssr(){
	if [[ -e ${shadowsocks_folder} ]];then
		echo -e "${Info} ShadowsocksR 文件夹已存在，请检查 ${shadowsocks_folder} 并且验证完整性"
	else
		cd ${shadowsocks_install_folder} && git clone -b master https://github.com/pandoraes/shadowsocksr-manyuser.git
	fi
}

check_install_config(){
	if [[ -e ${config} ]];then
		echo -e "${Info} ShadowsocksR 配置文件已存在，请检查 ${config} 并且验证完整性"
	else
		cd ${shadowsocks_folder} && cp config.json /etc/shadowsocksr/config.json
	fi
}


if_install(){
	[[ -d ${shadowsocks_folder} && -f ${config} ]] && {
		echo -e "${OK} ${GreenBG} ShadowsocksR 已安装 ${Font}"
	} || {
		echo -e "${Error} ${RedBG} ShadowsocksR 未安装，请在安装后执行相关操作 ${Font}"
		exit 1
	}
}

SSR_installation(){
#set config

#basic install	
	basic_installation
	dependency_installation
	development_tools_installation
	libsodium_installation
	check_install_ssr
	check_install_config
	SSR_dependency_installation
#final option
	iptables_OFF
	echo -e "${OK} ${GreenBG} SSR manyuser 安装完成 ${Font}"
	sleep 1
}

install_management(){
		check_system
		echo -e "${Red} 请选择安装内容 ${Font}"
		echo -e "1. SSR + supervisor"
		echo -e "2. SSR "
		echo -e "3. supervisor"
		read -p "input:" number
		case ${number} in
			1)
				SSR_installation
				supervisor_installation
				supervisor_conf_modify_${ID}
				;;
			2)
				SSR_installation
				;;
			3)
				supervisor_installation
				supervisor_conf_modify_${ID}
				;;
			*)
				echo -e "${Error} ${RedBG} 请输入正确的序号 ${Font}"
				exit 1			
				;;
		esac
}

uninstall_management(){
	if_install
	rm -rf ${shadowsocks_folder}
	echo -e "${OK$ {GreenBG} shadowsocks 卸载完成 ${Font}"
	exit 0
}

management(){
	case $1 in
		install)
			install_management
			;;
		uninstall)
			uninstall_management			
			;;
	esac
}
management $1

