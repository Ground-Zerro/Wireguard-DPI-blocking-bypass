## Обход блокировки протокола Wireguard на роутерах Keenetic

установить `cron` и `nping`:
```
opkg update && opkg upgrade
```
```
opkg install cron nping
```

В файле `/opt/etc/crontab` закомментируйте неиспользуемые строки, оставив только `cron.1min`:
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

Создать [скрипт](https://github.com/Ground-Zerro/Wireguard-DPI-blocking-bypass/blob/main/pinger), с именем `pinger` в папке `/opt/etc/cron.1min/`.

Изменить в скрипте `pinger`:
- в переменной `fey` указать номера интерфейсов WG в кавычках через пробел (не больше 5)
- в переменной `gateX` задать 3 значения через пробел, число `X` должно совпадать с номером интерфейса WG для которого вы указываете значения:
1. порт удаленного пира
2. адрес удаленного пира
3. адрес который будет проверяться на доступность. Это должен быть узел **куда не дойдет пинг когда VPN вЫключен**, например IP доступный только внутри сети WG либо DNS/IP недоступного в вашей стране ресурса.

Пример записи WG интерфейсов в файле `pinger`:
```
fey="39 44"
gate39="33825 193.115.214.218 site.com"
gate44="44569 96.112.125.108 46.163.88.20"
    ^   ^     ^              ^
    |   |     |              | IP или домен куда не пройдет пинг когда VPN вЫключен
    |   |     | IP WG сервера
    |   | порт WG сервера
    | номер nwg интерфейса в роутере, найти можно командой: ip a | grep nwg
```

После корректировки скрипта `pinger` дайте ему разрешения командой:
```
chmod 755 /opt/etc/cron.1min/pinger
```

Запускаем крон:

```
/opt/etc/init.d/S10cron start
```

**Логика работы скрипта pinger:**
- каждую минуту скрипт првоеряет включен ли интерфейс `nwgХ`, если включен, то:
- проверяется доступность указанного в `gateX` адреса,
- если на него не прошел пинг три раза подряд, запускается генерация случайного порта из диапазона 2000-65000 с проверкой его занятости,
- если порт занят, генерируется другой порт,
- запускается пинговка 8 раз по UDP с нового порта на пир WG,
- на интерфейсе WG устанавливается новый порт.

<details>
  <summary>Узнать возможные команды работы крон:</summary>
    
    
    /opt/etc/init.d/S10cron -?
    
Вывод:
`Usage: /opt/etc/init.d/S10cron (start|stop|restart|check|status|kill|reconfigure)`
</details>
