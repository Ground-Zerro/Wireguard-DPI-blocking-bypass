## Обход блокировки протокола Wireguard и AmneziaWG на роутерах Keenetic.

Установить OPKG пакеты `cron` и `nping`:
```
opkg update && opkg upgrade
```
```
opkg install cron nping
```

В файле `/opt/etc/crontab` закомментируйте неиспользуемые строки, для работы скрипта нужна `cron.1min`:
```
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/bin:/opt/sbin
MAILTO=""
HOME=/
# ---------- ---------- Default is Empty ---------- ---------- #
*/1 * * * * root /opt/bin/run-parts /opt/etc/cron.1min
#*/5 * * * * root /opt/bin/run-parts /opt/etc/cron.5mins
#01 * * * * root /opt/bin/run-parts /opt/etc/cron.hourly
#02 4 * * * root /opt/bin/run-parts /opt/etc/cron.daily
#22 4 * * 0 root /opt/bin/run-parts /opt/etc/cron.weekly
#42 4 1 * * root /opt/bin/run-parts /opt/etc/cron.monthly
```

В папке `/opt/etc/cron.1min/` создать [скрипт](https://github.com/Ground-Zerro/Wireguard-DPI-blocking-bypass/blob/main/pinger) с именем `pinger`.
```
#!/bin/sh
PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

fey="2 4 5"
gate2="23931 wg.vpn.org ya.ru 10.8.0.1"
gate4="35729 122.91.124.211 142.250.76.14"
gate5="51820 242.81.231.234 ya.ru"

gnip()
{
! ping -I nwg$1 -s0 -qc1 -W1 $2 >/dev/null 2>&1
}

for i in $fey; do
    ip a s nwg$i | grep -q UP || continue
    gate=$(eval echo \$gate$i)
    pgat="$i ${gate##* }"
    if gnip $pgat && gnip $pgat && gnip $pgat && gnip $pgat; then
        port=$(awk 'BEGIN{srand();print int(rand()*63000)+2000}')
        while netstat -nlu | grep -qw $port
        do
            port=$(awk 'BEGIN{srand();print int(rand()*63000)+2000}')
        done
        nping --udp --count 9 --source-port $port --data-length 64 --dest-port ${gate% *} >/dev/null 2>&1
        ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
    fi
done >/dev/null 2>&1
```

В скрипте изменить:
- в переменной `fey` указать номера интерфейсов WG в кавычках, через пробел (не больше 5)
- в переменной `gateX` задать 3 значения через пробел, число `X` должно совпадать с номером интерфейса WG для которого вы указываете значения:
1. порт удаленного пира
2. адрес удаленного пира
3. адрес используя который будет проверяться наличие на роутере выхода в интернет. Это может быть любой адрес в интернете (или корпоративной сети, если это необходимо).

Пример записи WG интерфейсов в файле `pinger`:
```
fey="2 4 5"
gate2="23931 wg.vpn.org ya.ru 10.8.0.1"
gate4="35729 122.91.124.211 142.250.76.14"
gate5="51820 242.81.231.234 ya.ru"
    ^  ^     ^              ^
    |  |     |              | IP или домен для проверки подключения роутера к интернету
    |  |     | IP или домен WG сервера
    |  | порт WG сервера
    | номер nwg интерфейса.
```

- Найти номер `nwg` интерфейса в роутере можно командой:
```
ip a | sed -n 's/[^ ]* \(nwg\)/\1/p'
```

Дать скрипту необходимые разрешения:
```
chmod 755 /opt/etc/cron.1min/pinger
```

Запустить крон:
```
/opt/etc/init.d/S10cron start
```

<details>
    <summary>Команды работы cron:</summary>
    
    /opt/etc/init.d/S10cron -?
    
Примерный вывод:
`Usage: /opt/etc/init.d/S10cron (start|stop|restart|check|status|kill|reconfigure)`
    
</details>

### Логика работы скрипта pinger:
Каждую минуту скрипт првоеряет включен ли интерфейс `nwgХ`, если включен, то:
- проверяется доступность указанного в `gateX` адреса,
- если на него не прошел пинг три раза подряд:
    - запускается генерация случайного порта из диапазона 2000-65000 с проверкой его занятости,
        - если порт занят, генерируется другой порт,
- запускается пинговка 8 раз по UDP с нового порта на пир WG,
- на интерфейсе WG устанавливается новый порт.

### Идея и код - [Frans](https://forum.keenetic.com/topic/19389-%D0%BE%D0%B1%D1%85%D0%BE%D0%B4-%D0%B1%D0%BB%D0%BE%D0%BA%D0%B8%D1%80%D0%BE%D0%B2%D0%BA%D0%B8-%D0%BF%D1%80%D0%BE%D1%82%D0%BE%D0%BA%D0%BE%D0%BB%D0%B0-wireguard-%D0%BD%D0%B5-amneziawg/?do=findComment&comment=193421).
