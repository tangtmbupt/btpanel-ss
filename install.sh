#!/bin/bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

PLUGIN_PATH=/www/server/panel/plugin/ss
SERVICE_NAME=shadowsocks-libev
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

# 防火墙操作
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
    echo "Installing shadowsocks-libev plugin..."

    # 安装 shadowsocks-libev
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y shadowsocks-libev
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y shadowsocks-libev
    else
        echo "Unsupported package manager. Install shadowsocks-libev manually."
        exit 1
    fi

    # 创建插件目录
    mkdir -p "$PLUGIN_PATH"
    cp -a ss_main.py icon.png info.json index.html install.sh "$PLUGIN_PATH/"

    # 创建用户
    id $SS_USER >/dev/null 2>&1 || groupadd $SS_USER
    id $SS_USER >/dev/null 2>&1 || useradd -s /sbin/nologin -M -g $SS_USER $SS_USER

    # 生成随机密码
    local password
    password=$(generate_password)

    # 写 shadowsocks 配置
    cat > "$PLUGIN_PATH/config.json" <<EOF
{
    "server":"0.0.0.0",
    "server_port":$SS_PORT,
    "password":"$password",
    "timeout":300,
    "method":"aes-256-cfb",
    "fast_open":false
}
EOF

    # 链接到系统默认位置
    cp "$PLUGIN_PATH/config.json" /etc/shadowsocks-libev/config.json
    chown $SS_USER:$SS_USER /etc/shadowsocks-libev/config.json

    # 启用 systemd 服务
    systemctl enable shadowsocks-libev
    systemctl restart shadowsocks-libev

    # 打开端口
    set_port $SS_PORT

    # 显示信息给用户
    echo
    echo "=================================================="
    echo "Shadowsocks installed successfully!"
    echo "Server IP: $(hostname -I | awk '{print $1}')"
    echo "Port: $SS_PORT"
    echo "Password: $password"
    echo "Method: aes-256-cfb"
    echo "=================================================="
    echo
}

uninstall_ss() {
    echo "Uninstalling shadowsocks-libev plugin..."

    systemctl stop shadowsocks-libev || true
    systemctl disable shadowsocks-libev || true

    rm -rf "$PLUGIN_PATH"
    rm -f /etc/shadowsocks-libev/config.json

    remove_port $SS_PORT

    id $SS_USER >/dev/null 2>&1 && userdel $SS_USER
    getent group $SS_USER >/dev/null 2>&1 && groupdel $SS_USER

    if command -v apt-get >/dev/null 2>&1; then
        apt-get remove -y shadowsocks-libev
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y shadowsocks-libev
    fi
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
