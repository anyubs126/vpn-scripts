#!/bin/bash
# REALITY一键安装脚本
# Author: YouTube频道<https://www.youtube.com/@aifenxiangdexiaoqie>

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

NAME="xray"
CONFIG_FILE="/usr/local/etc/${NAME}/config.json"
SERVICE_FILE="/etc/systemd/system/${NAME}.service"
DEFAULT_START_PORT=10000                      
IP_ADDRESSES=($(hostname -I))
declare -a USER_UUID PORT USER_NAME PRIVATE_KEY PUBLIC_KEY USER_DEST USER_SERVERNAME USER_SID LINK
	
colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`which yum 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        res=`which apt 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

status() {
    export PATH=/usr/local/bin:$PATH
    cmd="$(command -v xray)"
    if [[ "$cmd" = "" ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep -o '"port": [0-9]*' $CONFIG_FILE | awk '{print $2}' | head -n 1`
	if [[ -n "$port" ]]; then
        res=`ss -ntlp| grep ${port} | grep xray`
        if [[ -z "$res" ]]; then
            echo 2
        else
            echo 3
        fi
	else
	    echo 2
	fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装xray${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装xray${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装xray${PLAIN}
            ;;
    esac
}



preinstall() {
    $PMT clean all
    [[ "$PMT" = "apt" ]] && $PMT update
    echo ""
    echo "安装必要软件，请等待..."
    if [[ "$PMT" = "apt" ]]; then
		res=`which ufw 2>/dev/null`
        [[ "$?" != "0" ]] && $CMD_INSTALL ufw
	fi	
    res=`which curl 2>/dev/null`
    [[ "$?" != "0" ]] && $CMD_INSTALL curl
    res=`which openssl 2>/dev/null`
    [[ "$?" != "0" ]] && $CMD_INSTALL openssl
	res=`which qrencode 2>/dev/null`
    [[ "$?" != "0" ]] && $CMD_INSTALL qrencode
	res=`which jq 2>/dev/null`
    [[ "$?" != "0" ]] && $CMD_INSTALL jq

    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

# 定义域名列表
get_domain_list() {
    domains=(
        "one-piece.com"
        "www.lovelive-anime.jp"
        "www.swift.com"
        "academy.nvidia.com"
        "www.cisco.com"
        "www.samsung.com"
        "www.amd.com"
        "www.apple.com"
        "music.apple.com"
        "www.amazon.com"
        "www.fandom.com"
        "tidal.com"
        "zoro.to"
        "www.pixiv.co.jp"
        "mxj.myanimelist.net"
        "mora.jp"
        "www.j-wave.co.jp"
        "www.dmm.com"
        "booth.pm"
        "www.ivi.tv"
        "www.leercapitulo.com"
        "www.sky.com"
        "itunes.apple.com"
        "download-installer.cdn.mozilla.net"
    )
    echo "${domains[@]}"
}

# 快速验证并选择可用域名
select_valid_domain() {
    colorEcho $BLUE "正在验证可用域名，请稍候..."

    domains=($(get_domain_list))

    # 预设一些已知可用的域名作为备选
    backup_domains=(
        "www.apple.com"
        "music.apple.com"
        "www.amazon.com"
        "www.cisco.com"
        "academy.nvidia.com"
    )

    # 首先尝试备选域名（通常更稳定）
    for domain in "${backup_domains[@]}"; do
        colorEcho $YELLOW "测试域名: $domain"
        # 设置超时时间为5秒，减少等待时间
        if timeout 5 bash -c "echo QUIT | openssl s_client -connect ${domain}:443 -tls1_3 -alpn h2 2>/dev/null | grep -q 'TLSv1.3'" 2>/dev/null; then
            colorEcho $GREEN "✅ 选择域名: $domain"
            echo "$domain"
            return 0
        fi
    done

    # 如果备选域名都不可用，随机选择一个进行快速测试
    for i in {1..3}; do  # 最多尝试3次
        random_index=$((RANDOM % ${#domains[@]}))
        domain="${domains[random_index]}"
        colorEcho $YELLOW "测试域名: $domain (尝试 $i/3)"

        if timeout 3 bash -c "echo QUIT | openssl s_client -connect ${domain}:443 -tls1_3 -alpn h2 2>/dev/null | grep -q 'TLSv1.3'" 2>/dev/null; then
            colorEcho $GREEN "✅ 选择域名: $domain"
            echo "$domain"
            return 0
        fi
    done

    # 如果所有测试都失败，使用默认域名
    colorEcho $YELLOW "⚠️  使用默认域名: www.apple.com"
    echo "www.apple.com"
}


# 安装 Xray内核
installXray() {
    echo ""
    echo "正在安装Xray..."
    bash -c "$(curl -s -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" > /dev/null 2>&1
	colorEcho $BLUE "xray内核已安装完成"
	sleep 5
}

# 更新 Xray内核
updateXray() {
    echo ""
    echo "正在更新Xray..."
    bash -c "$(curl -s -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" > /dev/null 2>&1
	colorEcho $BLUE "xray内核已更新完成"
	sleep 5
}

removeXray() {
    echo ""
    echo "正在卸载Xray..."
    #systemctl stop xray
	#systemctl disable xray > /dev/null 2>&1
	#rm -rf /etc/systemd/system/xray*
	#rm /usr/local/bin/xray
    bash -c "$(curl -s -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge > /dev/null 2>&1
    rm -rf /etc/systemd/system/xray.service > /dev/null 2>&1
    rm -rf /etc/systemd/system/xray@.service > /dev/null 2>&1
    rm -rf /usr/local/bin/xray > /dev/null 2>&1
    rm -rf /usr/local/etc/xray > /dev/null 2>&1
    rm -rf /usr/local/share/xray > /dev/null 2>&1
    rm -rf /var/log/xray > /dev/null 2>&1
	colorEcho $RED "已完成xray卸载"
	sleep 5
}


# 创建配置文件 config.json
config_nodes() {

    read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
	START_PORT=${START_PORT:-$DEFAULT_START_PORT}

	# 🚀 优化：预先选择一个可用域名，所有节点共享使用
	SELECTED_DOMAIN=$(select_valid_domain)
	colorEcho $GREEN "所有节点将使用域名: $SELECTED_DOMAIN"

    # 开始生成 JSON 配置
    cat > /usr/local/etc/xray/config.json <<EOF
{
    "log": {
        "loglevel": "debug"
    },
    "inbounds": [
EOF

	colorEcho $BLUE "正在生成 ${#IP_ADDRESSES[@]} 个节点配置..."

	# 循环遍历 IP 和端口
	for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
		colorEcho $YELLOW "配置节点 $((i+1))/${#IP_ADDRESSES[@]} - IP: ${IP_ADDRESSES[i]}"

		# 生成 UUID
		/usr/local/bin/xray uuid > /usr/local/etc/xray/uuid
		USER_UUID[$i]=`cat /usr/local/etc/xray/uuid`

		# 生成节点名称
		USER_NAME[$i]="Reality(易小Q)_$i"

		# 生成私钥和公钥
		/usr/local/bin/xray x25519 > /usr/local/etc/xray/key
		PRIVATE_KEY[$i]=$(cat /usr/local/etc/xray/key | head -n 1 | awk '{print $3}')
		PUBLIC_KEY[$i]=$(cat /usr/local/etc/xray/key | sed -n '2p' | awk '{print $3}')

        # 开启端口
		PORT[$i]=$((START_PORT + i))
		colorEcho $YELLOW "开启端口: ${PORT[$i]}"

		# 🚀 优化：并行处理防火墙规则
		{
			if [ -x "$(command -v firewall-cmd)" ]; then
				firewall-cmd --permanent --add-port=${PORT[$i]}/tcp > /dev/null 2>&1
				firewall-cmd --permanent --add-port=${PORT[$i]}/udp > /dev/null 2>&1
			elif [ -x "$(command -v ufw)" ]; then
				ufw allow ${PORT[$i]}/tcp > /dev/null 2>&1
				ufw allow ${PORT[$i]}/udp > /dev/null 2>&1
			fi
		} &

		# 🚀 优化：使用预选的域名，无需重复检测
		USER_SERVERNAME[$i]="$SELECTED_DOMAIN"
		USER_DEST[$i]="${SELECTED_DOMAIN}:443"

		# 生成 short ID
        USER_SID[$i]=$(openssl rand -hex 8)

		echo "    {" >> /usr/local/etc/xray/config.json
		echo "      \"port\": ${PORT[$i]}," >> /usr/local/etc/xray/config.json
		echo "      \"protocol\": \"vless\"," >> /usr/local/etc/xray/config.json
		echo "      \"settings\": {" >> /usr/local/etc/xray/config.json
		echo "        \"clients\": [" >> /usr/local/etc/xray/config.json	
		echo "          {" >> /usr/local/etc/xray/config.json	
		echo "            \"id\": \"${USER_UUID[$i]}\"," >> /usr/local/etc/xray/config.json
		echo "            \"flow\": \"xtls-rprx-vision\"" >> /usr/local/etc/xray/config.json
		echo "          }" >> /usr/local/etc/xray/config.json	
		echo "        ]," >> /usr/local/etc/xray/config.json	
		echo "        \"decryption\": \"none\""  >> /usr/local/etc/xray/config.json
		echo "       },"  >> /usr/local/etc/xray/config.json
		echo "        \"streamSettings\": {"  >> /usr/local/etc/xray/config.json
		echo "            \"network\": \"tcp\","  >> /usr/local/etc/xray/config.json
		echo "            \"security\": \"reality\","  >> /usr/local/etc/xray/config.json
		echo "            \"realitySettings\": {"  >> /usr/local/etc/xray/config.json
		echo "                \"dest\": \"${USER_DEST[$i]}\","  >> /usr/local/etc/xray/config.json
		echo "                \"serverNames\": ["  >> /usr/local/etc/xray/config.json
		echo "                    \"${USER_SERVERNAME[$i]}\""  >> /usr/local/etc/xray/config.json
		echo "                ],"  >> /usr/local/etc/xray/config.json
		echo "                \"privateKey\": \"${PRIVATE_KEY[$i]}\","  >> /usr/local/etc/xray/config.json
		echo "                \"shortIds\": ["  >> /usr/local/etc/xray/config.json
		echo "                    \"\","  >> /usr/local/etc/xray/config.json
		echo "                    \"${USER_SID[$i]}\""  >> /usr/local/etc/xray/config.json
		echo "                ]"  >> /usr/local/etc/xray/config.json
		echo "            }"  >> /usr/local/etc/xray/config.json
		echo "        },"  >> /usr/local/etc/xray/config.json
		echo "        \"sniffing\": {"  >> /usr/local/etc/xray/config.json
		echo "            \"enabled\": true,"  >> /usr/local/etc/xray/config.json
		echo "            \"destOverride\": ["  >> /usr/local/etc/xray/config.json
		echo "                \"http\","  >> /usr/local/etc/xray/config.json
		echo "                \"tls\","  >> /usr/local/etc/xray/config.json
		echo "                \"quic\""  >> /usr/local/etc/xray/config.json
		echo "            ],"  >> /usr/local/etc/xray/config.json
		echo "            \"routeOnly\": true"  >> /usr/local/etc/xray/config.json
		echo "        }"  >> /usr/local/etc/xray/config.json
		# 如果不是最后一个元素，就加逗号
		if [ $i -lt $((${#IP_ADDRESSES[@]}-1)) ]; then
			echo "    }," >> /usr/local/etc/xray/config.json
		else
			echo "    }" >> /usr/local/etc/xray/config.json
		fi
    done

    # 等待所有后台防火墙任务完成
    wait

    # 🚀 优化：批量重载防火墙规则
    colorEcho $BLUE "正在应用防火墙规则..."
    if [ -x "$(command -v firewall-cmd)" ]; then
        firewall-cmd --reload > /dev/null 2>&1
        colorEcho $GREEN "✅ 防火墙规则已应用 (firewalld)"
    elif [ -x "$(command -v ufw)" ]; then
        ufw reload > /dev/null 2>&1
        colorEcho $GREEN "✅ 防火墙规则已应用 (ufw)"
    else
        colorEcho $YELLOW "⚠️  请手动配置防火墙规则"
    fi

	    # 结束 JSON 配置
	    cat >> /usr/local/etc/xray/config.json <<EOF
	],
	"outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
  ]
}
EOF

	colorEcho $GREEN "🎉 配置生成完成！正在启动服务..."
    restart
	generate_link
}


# 输出 VLESS 链接
generate_link() {
    > /root/link.txt
    colorEcho $BLUE "${BLUE}reality订阅链接${PLAIN}："
	# 循环遍历 IP 和端口
	for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
		if [[ "${IP_ADDRESSES[$i]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			LINK[$i]="vless://${USER_UUID[$i]}@${IP_ADDRESSES[$i]}:${PORT[$i]}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${USER_SERVERNAME[$i]}&fp=chrome&pbk=${PUBLIC_KEY[$i]}&sid=${USER_SID[$i]}&type=tcp&headerType=none#${USER_NAME[$i]}"
		elif [[ "${IP_ADDRESSES[$i]}" =~ ^([0-9a-fA-F:]+)$ ]]; then 
			LINK[$i]="vless://${USER_UUID[$i]}@[${IP_ADDRESSES[$i]}]:${PORT[$i]}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${USER_SERVERNAME[$i]}&fp=chrome&pbk=${PUBLIC_KEY[$i]}&sid=${USER_SID[$i]}&type=tcp&headerType=none#${USER_NAME[$i]}"
		else
			colorEcho $RED "没有获取到有效ip！"
		fi
	colorEcho $YELLOW ${LINK[$i]}
	echo ${LINK[$i]} >> /root/link.txt
	done
}	

start() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}xray未安装，请先安装！${PLAIN}"
        return
    fi
    systemctl restart ${NAME}
    sleep 2
    port=`grep -o '"port": [0-9]*' $CONFIG_FILE | awk '{print $2}' | head -n 1`
    res=`ss -ntlp| grep ${port} | grep xray`
    if [[ "$res" = "" ]]; then
        colorEcho $RED "xray启动失败，请检查端口是否被占用！"
    else
        colorEcho $BLUE "xray启动成功！"
    fi
}

restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}xray未安装，请先安装！${PLAIN}"
        return
    fi

    stop
    start
}

stop() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}xray未安装，请先安装！${PLAIN}"
        return
    fi
    systemctl stop ${NAME}
    colorEcho $BLUE "xray停止成功"
}



menu() {
    clear
    bash -c "$(curl -s -L https://raw.githubusercontent.com/yirenchengfeng1/linux/main/reality.sh)"
}

Xray() {
    clear
    echo "##################################################################"
    echo -e "#                   ${RED}Reality一键安装脚本${PLAIN}                                    #"
    echo -e "# ${GREEN}作者${PLAIN}: 爱分享的易小Q                                                     #"
    echo -e "# ${GREEN}网址${PLAIN}: @yxq666                     #"
	echo -e "# ${GREEN}VPS选购攻略${PLAIN}：@yxq666                     #"
	echo -e "# ${GREEN}年付10美金VPS推荐${PLAIN}：@yxq666     #"	
    echo "##################################################################"

    echo -e "  ${GREEN}  <Xray内核版本>  ${YELLOW}"	
    echo -e "  ${GREEN}1.${PLAIN}  安装xray"	
    echo -e "  ${GREEN}2.${PLAIN}  更新xray"
    echo -e "  ${GREEN}3.${RED}  卸载ray${PLAIN}"
    echo " -------------"	
    echo -e "  ${GREEN}4.${PLAIN}  搭建VLESS-Vision-uTLS-REALITY（xray）"
    echo -e "  ${GREEN}5.${PLAIN}  查看reality链接"
    echo " -------------"
    echo -e "  ${GREEN}6.${PLAIN}  启动xray"
    echo -e "  ${GREEN}7.${PLAIN}  重启xray"
    echo -e "  ${GREEN}8.${PLAIN}  停止xray"
    echo " -------------"
    echo -e "  ${GREEN}9.${PLAIN}  返回上一级菜单"	
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo -n " 当前xray状态："
	statusText
    echo 

    read -p " 请选择操作[0-10]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
		    checkSystem
            preinstall
	        installXray
			Xray
            ;;
        2)
	        updateXray
			Xray
            ;;	
        3)
            removeXray
            ;;			
		4)
            config_nodes
            ;;
        5)
			cat /root/link.txt 
            ;;
        6)
            start
			Xray
            ;;
        7)
            restart
			Xray
            ;;
        8)
            stop
			Xray
            ;;
		9)
			menu
            ;;
        *)
            echo " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

Xray "$@"
