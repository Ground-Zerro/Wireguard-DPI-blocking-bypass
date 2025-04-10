# Восстановление рукопожатия WireGuard и AmneziaWG на роутерах Keenetic

Скрипт восстанавливает "потерянное" рукопожатие WireGuard (в том числе AmneziaWG).

---

## 📌 Требования

- KeenOS версии 4.x
- Установленная среда [Entware](https://help.keenetic.com/hc/ru/articles/360021214160)

---

## ⚙️ Установщик (автоматический режим)

Отличия от варианта с `cron`:

- Срабатывает при изменении состояния любого интерфейса (например, при подключении/отключении интернета).
- Улучшенная генерация случайного порта, числа запросов и размера данных
- Блокировка повторного запуска до завершения текущего
- Можно запустить вручную простым выключением/включением любого соединения.

---

## ⏱ Работа через Cron (альтернативный режим)

1. Установите необходимые пакеты:
   ```sh
   opkg update && opkg upgrade
   opkg install cron nping
   ```

2. Отредактируйте файл `/opt/etc/crontab`. Пример:
   ```cron
   SHELL=/bin/sh
   PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/bin:/opt/sbin
   MAILTO=""
   HOME=/
   */1 * * * * root /opt/bin/run-parts /opt/etc/cron.1min
   ```

3. Создайте скрипт `/opt/etc/cron.1min/pinger` со следующим содержимым:
   ```sh
   #!/bin/sh
   PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

   gnip() {
     ! ping -I nwg$1 -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1
   }

   for i in $(ip a | sed -n 's/.*nwg\(.*\): <.*UP.*//p'); do
       rem=$(ndmc -c "show interface Wireguard$i" | sed -n 's/.*remote.*: \(.*\)/\1/p')
       echo $rem | grep -q '^0\| 0' && continue
       if gnip $i && gnip $i && gnip $i && gnip $i; then
           port=$(awk 'BEGIN{srand();print int(rand()*63000)+2000}')
           while netstat -nlu | grep -qw $port; do
               port=$(awk 'BEGIN{srand();print int(rand()*63000)+2000}')
           done >/dev/null 2>&1
           nping --udp --count 9 --source-port $port --data-length 64 --dest-port $(echo $rem | cut -f2 -d' ') ${rem%% *} >/dev/null 2>&1
           ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
       fi
   done
   ```

4. Сделайте скрипт исполняемым:
   ```sh
   chmod 755 /opt/etc/cron.1min/pinger
   ```

5. Запустите cron:
   ```sh
   /opt/etc/init.d/S10cron start
   ```

<details>
  <summary>📖 Полезные команды cron</summary>

  ```sh
  /opt/etc/init.d/S10cron -?
  ```

  Возможный вывод:
  ```
  Usage: /opt/etc/init.d/S10cron (start|stop|restart|check|status|kill|reconfigure)
  ```
</details>

---

## 🔍 Логика работы скрипта `pinger`

Каждую минуту скрипт:

- Проверяет доступность `1.1.1.1` через каждый интерфейс `nwg*` (WireGuard)
- Если пинг не проходит **4 раза подряд**, то:
  - Генерируется случайный UDP-порт (2000–65000)
  - Проверяется его незанятость
  - Выполняется 9 UDP-запросов (`nping`) с новым портом на текущий WG-пир
  - Меняется локальный listen-порт WireGuard интерфейса

> Пропускаются интерфейсы с `remote: 0.0.0.0 0` — это, как правило, серверные WG-интерфейсы без настроенного пира

---

## 👤 Автор идеи и кода

**Frans**  
Источник: [Форум Keenetic](https://forum.keenetic.ru/topic/19389-обход-блокировки-протокола-wireguard-в-тч-amneziawg/?do=findComment&comment=193941)
