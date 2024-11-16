#!/bin/sh

# Функция для получения списка интерфейсов WireGuard
get_wireguard_interfaces() {
    ip a | awk '/^[0-9]+: nwg/ {iface=$2} /inet / && iface {gsub(":", "", iface); print iface, $2}'
}

# Запрос выбора интерфейса WireGuard у пользователя
select_wireguard_interface() {
    echo "Поиск доступных WireGuard интерфейсов..."
    interfaces=$(get_wireguard_interfaces)
    
    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1
    fi

    echo "Доступные интерфейсы:"
    echo "$interfaces" | nl -w 2 -s '. '

    read -p "Введите номер интерфейса для использования: " choice
    selected=$(echo "$interfaces" | sed -n "${choice}p")

    if [ -z "$selected" ]; then
        echo "Неверный выбор. Завершение работы."
        exit 1
    fi

    echo "$selected" | awk '{print $1}'
}

# Основная часть скрипта
echo "Установка необходимых пакетов..."
opkg update
opkg install adguardhome-go ipset iptables ip-full

echo "Настройка AdGuard Home..."
opkg dns-override
system configuration save

# Получение интерфейса WireGuard
WG_INTERFACE=$(select_wireguard_interface)
if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard."
    exit 1
fi

echo "Выбран интерфейс WireGuard: $WG_INTERFACE"

# Создание скрипта для ipset
echo "Создание скрипта для ipset..."
cat << EOF > /opt/etc/init.d/S52ipset
#!/bin/sh

PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "\$1" = "start" ]; then
    ipset create bypass hash:ip
    ipset create bypass6 hash:ip family inet6
    ip rule add fwmark 1001 table 1001
    ip -6 rule add fwmark 1001 table 1001
fi
EOF

# Создание скриптов для маршрутов
echo "Создание скриптов маршрутизации..."
cat << EOF > /opt/etc/ndm/ifstatechanged.d/010-bypass-table.sh
#!/bin/sh

[ "\$system_name" == "$WG_INTERFACE" ] || exit 0
[ ! -z "\$(ipset --quiet list bypass)" ] || exit 0
[ "\${connected}-\${link}-\${up}" == "yes-up-up" ] || exit 0

if [ -z "\$(ip route list table 1001)" ]; then
    ip route add default dev \$system_name table 1001
fi
EOF

cat << EOF > /opt/etc/ndm/ifstatechanged.d/011-bypass6-table.sh
#!/bin/sh

[ "\$system_name" == "$WG_INTERFACE" ] || exit 0
[ ! -z "\$(ipset --quiet list bypass6)" ] || exit 0
[ "\${connected}-\${link}-\${up}" == "yes-up-up" ] || exit 0

if [ -z "\$(ip -6 route list table 1001)" ]; then
    ip -6 route add default dev \$system_name table 1001
fi
EOF

# Создание скриптов для маркировки трафика
echo "Создание скриптов для маркировки трафика..."
cat << EOF > /opt/etc/ndm/netfilter.d/010-bypass.sh
#!/bin/sh

[ "\$type" == "ip6tables" ] && exit
[ "\$table" != "mangle" ] && exit
[ -z "\$(ip link list | grep $WG_INTERFACE)" ] && exit
[ -z "\$(ipset --quiet list bypass)" ] && exit

if [ -z "\$(iptables-save | grep bypass)" ]; then
     iptables -w -t mangle -A PREROUTING ! -i $WG_INTERFACE -m conntrack --ctstate NEW -m set --match-set bypass dst -j CONNMARK --set-mark 1001
     iptables -w -t mangle -A PREROUTING ! -i $WG_INTERFACE -m set --match-set bypass dst -j CONNMARK --restore-mark
fi
EOF

cat << EOF > /opt/etc/ndm/netfilter.d/011-bypass6.sh
#!/bin/sh

[ "\$type" != "ip6tables" ] && exit
[ "\$table" != "mangle" ] && exit
[ -z "\$(ip -6 link list | grep $WG_INTERFACE)" ] && exit
[ -z "\$(ipset --quiet list bypass6)" ] && exit

if [ -z "\$(ip6tables-save | grep bypass6)" ]; then
     ip6tables -w -t mangle -A PREROUTING ! -i $WG_INTERFACE -m conntrack --ctstate NEW -m set --match-set bypass6 dst -j CONNMARK --set-mark 1001
     ip6tables -w -t mangle -A PREROUTING ! -i $WG_INTERFACE -m set --match-set bypass6 dst -j CONNMARK --restore-mark
fi
EOF

# Установка прав на выполнение скриптов
echo "Установка прав на выполнение скриптов..."
chmod +x /opt/etc/init.d/S52ipset
chmod +x /opt/etc/ndm/ifstatechanged.d/010-bypass-table.sh
chmod +x /opt/etc/ndm/ifstatechanged.d/011-bypass6-table.sh
chmod +x /opt/etc/ndm/netfilter.d/010-bypass.sh
chmod +x /opt/etc/ndm/netfilter.d/011-bypass6.sh

# Настройка AdGuard Home
echo "Настройка конфигурации AdGuard Home..."
sed -i 's|ipset_file: ""|ipset_file: /opt/etc/AdGuardHome/ipset.conf|' /opt/etc/AdGuardHome/AdGuardHome.yaml

# Перезапуск AdGuard Home
echo "Перезапуск AdGuard Home..."
/opt/etc/init.d/S99adguardhome restart

echo "Скрипт выполнен. Добавьте домены в /opt/etc/AdGuardHome/ipset.conf и перезапустите AdGuard Home."
