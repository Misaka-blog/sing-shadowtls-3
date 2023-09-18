#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

realip(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

instsingbox(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE}
    fi
    ${PACKAGE_INSTALL} wget curl sudo

    last_version=$(curl -s https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}')

    if [[ $SYSTEM == "CentOS" ]]; then
        wget -N --no-check-certificate https://github.com/SagerNet/sing-box/releases/download/v$last_version/sing-box_"$last_version"_linux_$(archAffix).rpm
        rpm -i sing-box_"$last_version"_linux_$(archAffix).rpm
        rm -f sing-box_"$last_version"_linux_$(archAffix).rpm
    else
        wget -N --no-check-certificate https://github.com/SagerNet/sing-box/releases/download/v$last_version/sing-box_"$last_version"_linux_$(archAffix).deb
        dpkg -i sing-box_"$last_version"_linux_$(archAffix).deb
        rm -f sing-box_"$last_version"_linux_$(archAffix).deb
    fi

    rm -f /etc/sing-box/config.json

    read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "使用在 Sing-box 节点的端口为：$port"

    read -p "设置 Sing-box 节点伪装网站地址 （去除https://） [回车世嘉maimai日本网站]：" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"
    yellow "使用在 Sing-box 节点的伪装网站为：$proxysite"

    passwd=$(openssl rand -base64 16)
    ss_pwd=$(sing-box generate rand --base64 16)

    cat << EOF > /etc/sing-box/config.json
{
  "inbounds": [
    {
      "type": "shadowtls",
      "listen": "::",
      "listen_port": $port,
      "version": 3,
      "users": [
        {
          "name": "misaka",
          "password": "$passwd"
        }
      ],
      "handshake": {
        "server": "$proxysite",
        "server_port": 443
      },
      "detour": "shadowsocks-in"
    },
    {
      "type": "shadowsocks",
      "tag": "shadowsocks-in",
      "listen": "127.0.0.1",
      "network": "tcp",
      "method": "2022-blake3-aes-128-gcm",
      "password": "$ss_pwd"
    }
  ]
}
EOF

    # 给 IPv6 地址加中括号
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    mkdir /root/sing-box
    cat << EOF > /root/sing-box/client.json
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 1080,
      "sniff": true,
      "set_system_proxy": true
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "method": "2022-blake3-aes-128-gcm",
      "password": "$ss_pwd",
      "detour": "shadowtls-out",
      "multiplex": {
        "enabled": true,
        "max_connections": 4,
        "min_streams": 4
      }
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-out",
      "server": "$last_ip",
      "server_port": $port,
      "version": 3,
      "password": "$passwd",
      "tls": {
        "enabled": true,
        "server_name": "$proxysite"
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "geosite": "cn",
        "geoip": "cn",
        "outbound": "direct"
      },
      {
        "geosite": "category-ads-all",
        "outbound": "block"
      }
    ]
  }
}
EOF

    systemctl daemon-reload
    systemctl start sing-box
    systemctl enable sing-box

    if [[ -n $(systemctl status sing-box 2>/dev/null | grep -w active) && -f '/etc/sing-box/config.json' ]]; then
        green "Sing-box 服务启动成功"
    else
        red "Sing-box 服务启动失败，请运行 systemctl status sing-box 查看服务状态并反馈，脚本退出" && exit 1
    fi

    showconf
}

unstsingbox(){
    systemctl stop sing-box
    systemctl disable sing-box
    ${PACKAGE_UNINSTALL} sing-box
    rm -rf /root/sing-box /etc/sing-box

    green "Sing-box 已彻底卸载完成"
}

startsingbox(){
    systemctl start sing-box-server
    systemctl enable sing-box-server >/dev/null 2>&1
}

stopsingbox(){
    systemctl stop sing-box-server
    systemctl disable sing-box-server >/dev/null 2>&1
}

singboxswitch(){
    yellow "请选择你需要的操作："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Sing-box"
    echo -e " ${GREEN}2.${PLAIN} 关闭 Sing-box"
    echo -e " ${GREEN}3.${PLAIN} 重启 Sing-box"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1 ) startsingbox ;;
        2 ) stopsingbox ;;
        3 ) stopsingbox && startsingbox ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/sing-box/config.json 2>/dev/null | sed -n 6p | awk '{print $2}' | tr -d ',' | awk -F ":" '{print $2}' | tr -d '"')
    
    read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Sing-box 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "使用在 Sing-box 节点的端口为：$port"

    sed -i "6s#$oldport#$port#g" /etc/sing-box/config.json
    sed -i "26s#$oldport#$port#g" /root/sing-box/client.json

    stopsingbox && startsingbox

    green "Sing-box 端口已成功修改为：$port"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changepasswd(){
    oldpasswd=$(cat /etc/sing-box/config.json 2>/dev/null | sed -n 11p | awk '{print $2}' | tr -d '"')
    oldss_pwd=$(cat /etc/sing-box/config.json 2>/dev/null | sed -n 26p | awk '{print $2}' | tr -d '"')
    passwd=$(openssl rand -base64 16)
    ss_pwd=$(sing-box generate rand --base64 16)

    sed -i "11s#$oldpasswd#$passwd#g" /etc/sing-box/config.json
    sed -i "28s#$oldpasswd#$passwd#g" /root/sing-box/client.json
    sed -i "26s#$oldss_pwd#$ss_pwd#g" /etc/sing-box/config.json
    sed -i "14s#$oldss_pwd#$ss_pwd#g" /root/sing-box/client.json

    stopsingbox && startsingbox

    green "Sing-box 节点密码已重置成功！"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeconf(){
    green "Sing-box 配置变更选择如下:"
    echo -e " ${GREEN}1.${PLAIN} 修改端口"
    echo -e " ${GREEN}2.${PLAIN} 重置密码"
    echo ""
    read -p " 请选择操作 [1-2]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changepasswd ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    yellow "客户端配置文件 client.json 内容如下，并保存到 /root/sing-box/client.json"
    red "$(cat /root/sing-box/client.json)"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#              ${RED} Sing-box+ShadowTLS  一键管理脚本${PLAIN}            #"
    echo -e "# ${GREEN}作者${PLAIN}: MisakaNo の 小破站                                  #"
    echo -e "# ${GREEN}博客${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitHub 项目${PLAIN}: https://github.com/Misaka-blog               #"
    echo -e "# ${GREEN}GitLab 项目${PLAIN}: https://gitlab.com/Misaka-blog               #"
    echo -e "# ${GREEN}Telegram 频道${PLAIN}: https://t.me/misakanocchannel              #"
    echo -e "# ${GREEN}Telegram 群组${PLAIN}: https://t.me/misakanoc                     #"
    echo -e "# ${GREEN}YouTube 频道${PLAIN}: https://www.youtube.com/@misaka-blog        #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Sing-box"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Sing-box${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Sing-box"
    echo -e " ${GREEN}4.${PLAIN} 修改 Sing-box 配置"
    echo -e " ${GREEN}5.${PLAIN} 显示 Sing-box 配置文件"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in
        1 ) instsingbox ;;
        2 ) unstsingbox ;;
        3 ) singboxswitch ;;
        4 ) changeconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu