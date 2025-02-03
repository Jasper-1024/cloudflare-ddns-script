#!/bin/bash

# CHANGE THESE
auth_email="xxxx@xxx.xxx"  #你的CloudFlare注册账户邮箱,your cloudflare account email address
auth_key="xxxxxxxxxxxxxxxx"   #你的cloudflare账户Globel ID ,your cloudflare Globel ID
zone_name="xxxxx.xxx"   #你的域名,your root domain address
record_name="xxx.xxxxx.xxx" #完整域名,your full domain address
eth_card="xxxxx"             #使用本地方式获取ip绑定的网卡，默认为eth0，仅本地方式有效,the default ethernet card is eth0

ip_file_v4="ip_v4.txt"
ip_file_v6="ip_v6.txt"
id_file="cloudflare.ids"
log_file="cloudflare.log"

# set -x

# 日志函数保持不变
log() {
    if [ "$1" ]; then
        echo -e "[$(date)] - $1" >> $log_file
    fi
}

# 配置部分
update_a_record="yes"      # 是否更新A记录 (yes/no)
update_aaaa_record="yes"   # 是否更新AAAA记录 (yes/no)
ipv4_source="remote"       # IPv4获取方式 (remote/local)
ipv6_source="local"        # IPv6获取方式 (remote/local)

# 获取IPv4地址
get_ipv4() {
    local source=$1
    local ipv4
    if [ "$source" = "remote" ]; then
        ipv4=$(curl -4 ip.sb)
    elif [ "$source" = "local" ]; then
        if [ "$user" = "root" ]; then
            ipv4=$(ifconfig $eth_card | grep 'inet ' | awk '{print $2}')
        else
            ipv4=$(/sbin/ifconfig $eth_card | grep 'inet ' | awk '{print $2}')
        fi
    fi
    echo $ipv4
}

# 获取IPv6地址
get_ipv6() {
    local source=$1
    local ipv6
    if [ "$source" = "remote" ]; then
        ipv6=$(curl -6 ip.sb)
    elif [ "$source" = "local" ]; then
        if [ "$user" = "root" ]; then
            ipv6=$(ifconfig $eth_card | grep 'inet6'| grep -v '::1'|grep -v 'fe80' | cut -f2 | awk '{ print $2}' | head -1)
        else
            ipv6=$(/sbin/ifconfig $eth_card | grep 'inet6'| grep -v '::1'|grep -v 'fe80' | cut -f2 | awk '{ print $2}' | head -1)
        fi
    fi
    echo $ipv6
}

# 更新DNS记录
update_dns_record() {
    local record_type=$1
    local ip=$2
    local ip_file=$3
    
    # 检查IP是否变化
    if [ -f $ip_file ]; then
        old_ip=$(cat $ip_file)
        if [ "$ip" == "$old_ip" ]; then
            echo "$record_type record IP has not changed."
            return 0
        fi
    fi

    # 获取zone和record标识符
    if [ ! -f $id_file ] || [ $(wc -l $id_file | cut -d " " -f 1) != 4 ]; then
        # 获取zone标识符
        zone_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
            -H "X-Auth-Email: $auth_email" \
            -H "X-Auth-Key: $auth_key" \
            -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
        
        # 获取A记录标识符
        record_identifier_v4=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
            -H "X-Auth-Email: $auth_email" \
            -H "X-Auth-Key: $auth_key" \
            -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
        
        # 获取AAAA记录标识符
        record_identifier_v6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
            -H "X-Auth-Email: $auth_email" \
            -H "X-Auth-Key: $auth_key" \
            -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
        
        # 保存所有标识符
        echo "$zone_identifier" > $id_file
        echo "$record_identifier_v4" >> $id_file
        echo "$record_identifier_v6" >> $id_file
    fi

    # 读取标识符
    zone_identifier=$(sed -n '1p' $id_file)
    record_identifier_v4=$(sed -n '2p' $id_file)
    record_identifier_v6=$(sed -n '3p' $id_file)
    
    # 选择正确的record标识符
    record_identifier=$([ "$record_type" = "A" ] && echo "$record_identifier_v4" || echo "$record_identifier_v6")

    # 更新DNS记录
    update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
        -H "X-Auth-Email: $auth_email" \
        -H "X-Auth-Key: $auth_key" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}")

    # 检查更新结果
    if [[ "$(echo $update | grep -Po '(?<="content":")[^"]*' | head -1)" == "$ip" ]]; then
        message="$record_type record IP changed to: $ip"
        echo "$ip" > $ip_file
        log "$message"
        echo "$message"
    else
        message="API UPDATE FAILED for $record_type record. DUMPING RESULTS:\n$update"
        log "$message"
        echo -e "$message"
        return 1
    fi
}

# 主程序
log "Check Initiated"

# 更新IPv4记录
if [ "$update_a_record" = "yes" ]; then
    ipv4=$(get_ipv4 "$ipv4_source")
    if [ -n "$ipv4" ]; then
        update_dns_record "A" "$ipv4" "$ip_file_v4"
    else
        log "Failed to get IPv4 address from $ipv4_source source"
    fi
fi

# 更新IPv6记录
if [ "$update_aaaa_record" = "yes" ]; then
    ipv6=$(get_ipv6 "$ipv6_source")
    if [ -n "$ipv6" ]; then
        update_dns_record "AAAA" "$ipv6" "$ip_file_v6"
    else
        log "Failed to get IPv6 address from $ipv6_source source"
    fi
fi














