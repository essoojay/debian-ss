#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail #-o xtrace

check_if_running_as_root()
{
    if [[ $UID -ne 0 ]]
    then
        echo -e "\033[31mNot running with root, exiting...\033[0m"
        exit 1
    fi
}

check_if_running_in_container()
{
    if [[ $(ps --pid 1 | grep -v PID | awk '{print $4}') != "systemd" ]]
    then
        echo -e "\033[31mRunning in containers is not supported, exiting ...\033[0m"
        exit 2
    fi
}

check_os_version()
{
    if [[ $(lsb_release -is 2>&1) != "Debian" ]]
    then
        echo -e "\033[31mUnsupported linux distro!\033[0m"
        exit 3
    fi

    if [[ $(lsb_release -cs 2>&1) != "buster" &&
          $(lsb_release -cs 2>&1) != "bullseye" &&
          $(lsb_release -cs 2>&1) != "bookworm" ]]
    then
        echo -e "\033[31mUnsupported debian version!\033[0m"
        exit 4
    fi
}

install_packages()
{
    apt-get update
    apt-get upgrade -y
    apt-get install -y aptitude
    aptitude search ~pstandard ~prequired ~pimportant -F%p | xargs apt-get install -y
    apt-get install -y docker.io docker-compose unzip
}

enable_bbr()
{
    if [[ $(lsmod | awk '{print $1}' | grep 'tcp_bbr') == "tcp_bbr" ]] || modprobe tcp_bbr
    then
        if [[ $(grep '^tcp_bbr' /etc/modules-load.d/modules.conf) == "" ]]
        then
            echo "tcp_bbr" >>/etc/modules-load.d/modules.conf
        fi

        if [[ $(grep '^net.core.default_qdisc.*=' /etc/sysctl.conf) == "" ]]
        then
            echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
        else
            sed -i -e 's/net\.core\.default_qdisc.*=.*$/net\.core\.default_qdisc = fq/g' /etc/sysctl.conf
        fi

        if [[ $(grep '^net.ipv4.tcp_congestion_control.*=' /etc/sysctl.conf) == "" ]]
        then
            echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
        else
            sed -i -e 's/net\.ipv4\.tcp_congestion_control.*=.*$/net\.ipv4\.tcp_congestion_control = bbr/g' /etc/sysctl.conf
        fi

        sysctl -p

        echo -e "Enable bbr ... \033[32m[done]\033[0m."
    else
        echo -e "Enable bbr ... \033[33m[cancel] This kernel don't support BBR.\033[0m"
    fi
}

download_res()
{
    if ! curl -fsSL 'https://github.com/zmyxpt/debian-ss/archive/refs/heads/main.zip' -o debian-ss.zip
    then
        echo -e "\033[31mFail to download debian-ss resource, exiting...\033[0m"
        exit 5
    fi

    unzip -o debian-ss.zip
    rm debian-ss.zip
}

configure()
{
    set +x

    if [[ ! -e Volumes ]]
    then
        mkdir -p Volumes/shadowsocks
        mkdir -p Volumes/caddyfile
        mkdir -p Volumes/caddydata
    fi

    local domains email path sspassword
    read -r -p $'Set your domains, splite them with space, e.g. \033[1mexample.com www.example.com\033[0m\n' domains
    read -r -p $'Set your email, e.g. \033[1mabc@gmail.com\033[0m\n' email
    read -r -p $'Set your websocket path, e.g. \033[1m/path_to_ws\033[0m\n' path
    read -r -p $'Set your shadowsocks password, e.g. \033[1mpass1234\033[0m\n' sspassword

    local finish=false
    until "$finish"
    do
        echo $'Here is your setting:\n=============================='
        echo -e "Domains: \033[32m${domains}\033[0m"
        echo -e "Email: \033[32m${email}\033[0m"
        echo -e "Path: \033[32m${path}\033[0m"
        echo -e "Password: \033[32m${sspassword}\033[0m"
        echo $'===============================\nYou can:'
        echo "1. Reset domains"
        echo "2. Reset email"
        echo "3. Reset websocket path"
        echo "4. Reset shadowsocks password"
        echo "0. Finish it, start up"
        read -r -p $'Choose an option by number:\n' choice
        case "$choice" in
        1)
            read -r -p $'Set your domains, splite them with space, e.g. \033[1mexample.com www.example.com\033[0m\n' domains
            ;;
        2)
            read -r -p $'Set your email, e.g. \033[1mabc@gmail.com\033[0m\n' email
            ;;
        3)
            read -r -p $'Set your websocket path, e.g. \033[1m/path_to_ws\033[0m\n' path
            ;;
        4)
            read -r -p $'Set your shadowsocks password, e.g. \033[1mpass1234\033[0m\n' sspassword
            ;;
        0)
            finish=true
            ;;
        *) ;;
        esac
    done

    set -x

    cp Samples/shadowsocks.sample Volumes/shadowsocks/config.json
    cp Samples/Caddyfile.sample Volumes/caddyfile/Caddyfile

    sed -i -e "s/domains/${domains}/g" Volumes/caddyfile/Caddyfile
    sed -i -e "s/email/${email}/g" Volumes/caddyfile/Caddyfile
    sed -i -e "s/path/${path:1}/g" Volumes/caddyfile/Caddyfile
    sed -i -e "s/sspassword/${sspassword}/g" Volumes/shadowsocks/config.json
}

run_server()
{    
    if [[ $(lsof -i :443 | grep 'docker' | grep -v 'grep') != "" ]]
    then
        docker-compose -f docker_compose.yaml down
    fi

    docker-compose -f docker_compose.yaml up -d --build
}

main()
{
    local old_PWD
    old_PWD=$PWD

    check_if_running_as_root
    check_if_running_in_container
    check_os_version
    install_packages
    enable_bbr

    cd "$HOME"
    download_res

    cd debian-ss-main
    configure
    run_server

    cd "$old_PWD"
    echo "Done"
}

main
