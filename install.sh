#!/bin/sh

opkg update
opkg install nping

cat << 'EOF' > /opt/etc/ndm/netfilter.d/wgpass.sh
#!/bin/sh

if ps | grep -v grep | grep "wgpass.sh" | grep -qv "$$"; then
    exit 0
fi

maxtry=4

gnip() { ! ping -I "nwg$1" -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; }

for i in $(ip a | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
	rem=$(ndmc -c "show interface Wireguard$i" | sed -n 's/.*remote.*: \(.*\)/\1/p')
	echo "$rem" | grep -Eq '^0| 0' && continue

	try=1
	if gnip "$i" && gnip "$i" && gnip "$i"; then
		while [ $try -le $maxtry ]; do
			logger "WG bypass: START try $try for Wireguard$i."

			port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 63000) + 2000}')
			while ss -unl | grep -qw "$port"; do
				port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 63000) + 2000}')
			done >/dev/null 2>&1

			count=$(hexdump -n1 -e '1/1 "%u\n"' /dev/urandom | awk '{print ($1 % 21) + 30}')
			rate=$(hexdump -n1 -e '1/1 "%u\n"' /dev/urandom | awk '{print ($1 % 31) + 80}')
			length=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom | awk '{print ($1 % 1537) + 512}')
			rem_ip=$(echo "$rem" | head -n1)
			rem_port=$(echo "$rem" | tail -n1)
			nping --udp --count "$count" --rate "$rate" --source-port "$port" --data-length "$length" --dest-port "$rem_port" "$rem_ip" >/dev/null 2>&1
			ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
			sleep 10

			if gnip "$i"; then
				logger "WG bypass: FAIL for Wireguard$i. Retrying..."
				try=$((try + 1))
				if [ $try -gt $maxtry ]; then
					logger "WG bypass: GIVING UP after $maxtry tries for Wireguard$i."
					break
				fi
			else
				logger "WG bypass: SUCCESS for Wireguard$i on try $try."
				break
			fi
		done
	else
		logger "WG bypass: Wireguard$i already OK."
		continue
	fi
done
EOF
chmod +x /opt/etc/ndm/netfilter.d/wgpass.sh

echo "wg unlock install complete."

[ -f "$0" ] && rm "$0"
