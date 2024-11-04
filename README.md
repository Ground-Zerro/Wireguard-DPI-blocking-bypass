установить cron и nping:
```
opkg update && opkg upgrade
```
```
opkg install cron nping
```

В файле /opt/etc/crontab удалите неиспользуемые строки, нам нужна cron.1min:
```
*/1 * * * * root /opt/bin/run-parts /opt/etc/cron.1min
*/5 * * * * root /opt/bin/run-parts /opt/etc/cron.5mins
01 * * * * root /opt/bin/run-parts /opt/etc/cron.hourly
02 4 * * * root /opt/bin/run-parts /opt/etc/cron.daily
22 4 * * 0 root /opt/bin/run-parts /opt/etc/cron.weekly
42 4 1 * * root /opt/bin/run-parts /opt/etc/cron.monthly
```

Cоздаем [скрипт](https://github.com/Ground-Zerro/Wireguard-DPI-blocking-bypass/blob/main/pinger), например с именем `pinger` в папке `/opt/etc/cron.1min/`, который будет запускаться кроном каждую минуту.

- в переменной `fey` задаем номера интерфейсов WG через пробел, в кавычках (не больше 5), которые мы будем проверять каждую минуту, номера интерфейсов можете посмотреть командой: `ip a | grep nwg`
в переменных gateX указываются 3 значения через пробел, число X должно совпадать с номером интерфейса WG для которого вы указываете значения:
1. порт удаленного пира
2. адрес удаленного пира
3. адрес который будет проверяться на доступность, обычно это шлюз внутри сети WG или другой

Каждую минуту проверяется включен ли интерфейс nwgХ, если включен, то:
- проверяется доступность указанного в gateX адреса, если на него не прошел пинг три раза подряд,
- запускается генерация случайного порта из диапазона 2000-65000 с проверкой его занятости, если занят, генерируется другой порт
- запускается пинговка 8 раз по UDP с нового порта на пир WG
- на интерфейсе WG устанавливается новый порт.

После создания файла дайте ему разрешения командой:
```
chmod 755 /opt/etc/cron.1min/pinger
```

Проверяем возможные команды и запускаем крон:
```
~ # /opt/etc/init.d/S10cron -?
Usage: /opt/etc/init.d/S10cron (start|stop|restart|check|status|kill|reconfigure)
/opt/etc/init.d/S10cron start
```
