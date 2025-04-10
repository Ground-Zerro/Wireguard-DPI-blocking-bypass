#!/bin/sh

opkg update
opkg install nping

cat << 'EOF' > /opt/etc/ndm/netfilter.d/wgpass.sh
#!/bin/sh
PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

sleep 5

LOCK="/dev/wgun.lock"

if [ -e "$LOCK" ]; then
    exit
fi

touch "$LOCK"

trap "rm -f $LOCK" EXIT INT TERM

gnip()
{
! ping -I nwg$1 -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1
}

for i in $(ip a | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
    rem=$(echo $(ndmc -c "show interface Wireguard$i" | sed -n 's/.*remote.*: \(.*\)/\1/p'))
    echo $rem | grep -q '^0\| 0' && continue
    if gnip $i && gnip $i && gnip $i && gnip $i; then
        port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 63000) + 2000}')
        while netstat -nlu | grep -qw $port; do
            port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 63000) + 2000}')
        done >/dev/null 2>&1
        count=$(hexdump -n1 -e '1/1 "%u\n"' /dev/urandom | awk '{print ($1 % 5) + 6}')
        length=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 65) + 64}')
        nping --udp --count $count --source-port $port --data-length $length --dest-port $(echo $rem | cut -f2 -d' ') ${rem%% *} >/dev/null 2>&1
        ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
    fi
done

exit
EOF
chmod +x /opt/etc/ndm/netfilter.d/wgpass.sh