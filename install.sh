#!/bin/bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

PLUGIN_PATH=/www/server/panel/plugin/ss
SERVICE_NAME=ss
SS_USER=ssuser
SS_PORT=62443

# 检查 BT-Panel 是否安装
if [ ! -f /etc/init.d/bt ]; then
    echo "No BT-Panel is installed, please go to http://www.bt.cn to install."
    exit 1
fi

# 生成随机密码
generate_password() {
    openssl rand -hex 8
}

# 防火墙操作函数
firewall_op() {
    local port=$1
    local action=$2  # allow/delete

    if command -v ufw >/dev/null 2>&1; then
        ufw $action $port/tcp
        ufw $action $port/udp
        ufw reload
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --zone=public --${action}-port=${port}/tcp
        firewall-cmd --permanent --zone=public --${action}-port=${port}/udp
        firewall-cmd --reload
    fi

    if command -v iptables >/dev/null 2>&1; then
        if [ "$action" == "allow" ]; then
            iptables -I INPUT -p tcp -m state --state NEW --dport $port -j ACCEPT
            iptables -I INPUT -p udp -m state --state NEW --dport $port -j ACCEPT
        else
            iptables -D INPUT -p tcp -m state --state NEW --dport $port -j ACCEPT || true
            iptables -D INPUT -p udp -m state --state NEW --dport $port -j ACCEPT || true
        fi
        [ -f /etc/init.d/iptables ] && /etc/init.d/iptables save
    fi
}

set_port() {
    firewall_op "$1" allow
}

remove_port() {
    firewall_op "$1" delete
}

install_ss() {
    echo "Installing Shadowsocks plugin..."

    apt-get update
    apt-get install -y python3-pip python3-setuptools python3-dev build-essential

    python3 -m pip install --upgrade pip
    python3 -m pip install https://github.com/shadowsocks/shadowsocks/archive/master.zip m2crypto

    mkdir -p "$PLUGIN_PATH"
    cp -a ss_main.py icon.png info.json index.html install.sh ss.init shadowsocks.zip shadowsocks-nightly-4.2.5.apk "$PLUGIN_PATH/"
    cp -a ss.init /etc/init.d/ss
    chmod +x /etc/init.d/ss

    # systemd 启用服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable "$SERVICE_NAME" || true
    else
        chkconfig --add "$SERVICE_NAME"
        chkconfig --level 2345 "$SERVICE_NAME" on
    fi

    local password
    password=$(generate_password)

    # 写配置文件
    cat > "$PLUGIN_PATH/config.json" <<EOF
{
    "server":"0.0.0.0",
    "local_address":"127.0.0.1",
    "local_port":1080,
    "port_password":{
        "$SS_PORT":"$password"
    },
    "timeout":300,
    "method":"aes-256-cfb",
    "fast_open":false
}
EOF

    # 创建用户组和用户
    id $SS_USER >/dev/null 2>&1 || groupadd $SS_USER
    id $SS_USER >/dev/null 2>&1 || useradd -s /sbin/nologin -M -g $SS_USER $SS_USER
    chown $SS_USER:$SS_USER "$PLUGIN_PATH/config.json"

    set_port $SS_PORT
    /etc/init.d/ss start
    echo "Installation completed. Shadowsocks password for port $SS_PORT: $password"
}

uninstall_ss() {
    echo "Uninstalling Shadowsocks plugin..."
    /etc/init.d/ss stop || true

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable "$SERVICE_NAME" || true
    else
        chkconfig --del "$SERVICE_NAME" || true
    fi

    rm -f /etc/init.d/ss
    rm -rf "$PLUGIN_PATH"
    python3 -m pip uninstall shadowsocks -y || true

    id $SS_USER >/dev/null 2>&1 && userdel $SS_USER
    getent group $SS_USER >/dev/null 2>&1 && groupdel $SS_USER
    remove_port $SS_PORT
}

# 主逻辑
case "${1:-}" in
    install)
        install_ss
        ;;
    uninstall)
        uninstall_ss
        ;;
    port)
        set_port "$2"
        ;;
    rmport)
        remove_port "$2"
        ;;
    *)
        while [[ "$isInstall" != "y" && "$isInstall" != "n" ]]; do
            read -p "Do you really want to install ss-plugin to BT-Panel?(y/n): " isInstall
        done
        if [[ "$isInstall" =~ ^[yY]$ ]]; then
            install_ss
        fi
        ;;
esac
