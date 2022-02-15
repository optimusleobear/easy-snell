#!/usr/bin/env bash

export PATH=$PATH:~/bin

cd ~/

CONF="/etc/snell/snell-server.conf"
SYSTEMD="/etc/systemd/system/snell.service"

exiterr() { echo "Error: $1" >&2; exit 1; }

check_root() {
    if [ "$(id -u)" != 0 ]; then
        exiterr "Script must be run under root. Try 'sudo su' to switch to root user."
    fi
}

check_os() {
    os_type=centos
    rh_file="/etc/redhat-release"
    if grep -qs "Red Hat" "$rh_file"; then
        os_type=rhel
    fi
    if grep -qs "release 7" "$rh_file"; then
        os_ver=7
        yum install unzip wget -y
    elif grep -qs "release 8" "$rh_file"; then
        os_ver=8
        grep -qi stream "$rh_file" && os_ver=8s
        grep -qi rocky "$rh_file" && os_type=rocky
        grep -qi alma "$rh_file" && os_type=alma
        dnf install unzip wget -y
    elif grep -qs "Amazon Linux release 2" /etc/system-release; then
        os_type=amzn
        os_ver=2
        yum install unzip wget -y
    else
        os_type=$(lsb_release -si 2>/dev/null)
        [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
        case $os_type in
            [Uu]buntu)
            os_type=ubuntu
            ;;
            [Dd]ebian)
            os_type=debian
            ;;
            [Rr]aspbian)
            os_type=raspbian
            ;;
            *)
cat 1>&2 <<'EOF'
Error: This script only supports one of the following OS:
    Ubuntu, Debian, CentOS/RHEL 7/8, Rocky Linux, AlmaLinux,
    Amazon Linux 2.
EOF
            exit 1
            ;;
        esac
        apt-get install unzip wget -y
    fi
}


preparation() {
    wget --no-check-certificate -O snell.zip https://github.com/surge-networks/snell/releases/download/v3.0.1/snell-server-v3.0.1-linux-amd64.zip
    
    unzip -o snell.zip
    rm -f snell.zip

    chmod +x snell-server
    mv -f snell-server /usr/local/bin/
}

config_gen() {
    if [ -f ${CONF} ]; then
        echo "Found existing config..."
    else
        if [ -z ${PSK} ]; then
            PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
            echo "Using generated PSK: ${PSK}"
        else
            echo "Using predefined password: ${PSK}"
        fi
        mkdir /etc/snell/
        echo "Generating new config..."
        echo "[snell-server]" >>${CONF}
        echo "listen = 0.0.0.0:13254" >>${CONF}
        echo "psk = ${PSK}" >>${CONF}
        echo "obfs = tls" >>${CONF}
    fi
}

snell_installer() {
    status=0

    if [ -f ${SYSTEMD} ]; then
        echo "Found existing service..."
        systemctl daemon-reload
        systemctl restart snell
    else
        echo "Generating new service..."
        echo "[Unit]" >>${SYSTEMD}
        echo "Description=Snell Proxy Service" >>${SYSTEMD}
        echo "After=network.target" >>${SYSTEMD}
        echo "" >>${SYSTEMD}
        echo "[Service]" >>${SYSTEMD}
        echo "Type=simple" >>${SYSTEMD}
        echo "LimitNOFILE=32768" >>${SYSTEMD}
        echo "ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf" >>${SYSTEMD}
        echo "" >>${SYSTEMD}
        echo "[Install]" >>${SYSTEMD}
        echo "WantedBy=multi-user.target" >>${SYSTEMD}
        systemctl daemon-reload
        systemctl enable snell
        systemctl start snell
    fi
}

snell_setup() {
    check_root
    check_os
    preparation
    config_gen
    snell_installer
}

snell_setup "%@"

exit "$status"