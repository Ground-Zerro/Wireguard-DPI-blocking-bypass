#!/bin/sh

# Функция для получения списка интерфейсов WireGuard
get_wireguard_interfaces() {
    # Используем новый метод для поиска интерфейсов WireGuard
    for i in $(ip a | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
        rem=$(echo $(ndmc -c "show interface Wireguard$i" | sed -n 's/.*remote.*: \(.*\)/\1/p'))
        echo $rem | grep -q '^0\| 0' && continue
        echo "nwg$i"
    done
}

# Функция отключения системного DNS-сервера роутера
rci_post() {
    $WGET -qO - --post-data="$1" localhost:79/rci/ > /dev/null 2>&1
}

# Функция выбора интерфейса WireGuard
select_wireguard_interface() {
    echo "Поиск доступных WireGuard интерфейсов..."
    interfaces=$(get_wireguard_interfaces)

    if [ -z "$interfaces" ]; then
        echo "Не найдено активных WireGuard интерфейсов."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "Найдено $(echo "$interfaces" | wc -l) интерфейсов WireGuard."
    echo "Введите номер интерфейса для использования:"

    # Формируем список для выбора
    echo "$interfaces" | awk '{printf "%d. %s\n", NR, $1}'

    read -p "Ваш выбор: " choice
    selected=$(echo "$interfaces" | awk -v num="$choice" 'NR == num {print $1}')

    if [ -z "$selected" ]; then
        echo "Неверный выбор. Завершаем выполнение скрипта."
        exit 1  # Завершаем выполнение всего скрипта при ошибке
    fi

    echo "$selected"
}

# Основная часть скрипта
echo "Установка необходимых пакетов..."
opkg update
opkg install adguardhome-go ipset iptables ip-full

echo "Настройка AdGuard Home..."
WGET='/opt/bin/wget -q --no-check-certificate'

# Выполняем команду отключения DNS провайдера
curl -s "http://localhost:79/rci/opkg/dns-override" | grep -q true || {
    echo 'Отключаем работу через DNS-провайдера роутера...'
    echo "Возможно, что сейчас произойдет выход из сессии..."
    echo "В этом случае необходимо заново войти в сессию по ssh"
    echo "и запустить скрипт заново"
    rci_post '[{"opkg": {"dns-override": true}},{"system": {"configuration": {"save": true}}}]' &>/dev/null
}

# Получение интерфейса WireGuard
WG_INTERFACE=$(select_wireguard_interface)
if [ -z "$WG_INTERFACE" ]; then
    echo "Ошибка: не удалось определить интерфейс WireGuard."
    exit 1  # Завершаем выполнение всего скрипта при ошибке
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
