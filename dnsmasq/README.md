# DNSMASQ в контейнерах

## Назначение

Данное руководство описывает процесс развертывания DNS-сервера dnsmasq в контейнерах Docker/Podman. Решение предназначено для организации локального DNS-сервиса с поддержкой статических записей и перенаправления к внешним DNS-серверам.

## Конфигурационные файлы

### docker-compose.yml
- Используется сеть bridge
- Порт 53 публикуется на всех интерфейсах хоста (0.0.0.0:53)
- Конфигурационный файл монтируется как volume
- Сервис запускается с привилегиями NET_ADMIN

### dnsmasq.conf
- Слушает на всех интерфейсах (listen-address=0.0.0.0)
- Поддерживает статические записи через директиву address=/
- Использует указанные upstream DNS-серверы
- Включена проверка приватных адресов (bogus-priv)
- Включено использование resolv.conf

## Быстрый старт

1. **Создать конфиг из шаблона dnsmasq.conf.template:**
   ```bash
   cp ./dnsmasq.conf.template ./dnsmasq.conf
   vi ./dnsmasq.conf
   ```
   Пример dnsmasq.conf
   ```bash
   port=53
   # Custom DNS records
   address=/hostname.example.com/192.168.1.100
   ```
2. **На хосте dnsmasq (server DNS) выполнить команду compose:**
   ```bash
   sudo podman compose -f ./docker-compose.yml up -d
   ```
3. **На клиентских (client) узлах изменить DNS server в /etc/resolv.conf:**
      ```bash
      # Backup original resolv.conf
      cp /etc/resolv.conf /etc/resolv.conf.backup
      # Create new resolv.conf with only our DNS server
      echo -e \"# Custom DNS (dnsmasq) server\\nnameserver $DNS_SERVER_IP\" > /etc/resolv.conf
      ```
      
## Проверка работоспособности

На клиентских (client) узлах выполнить команду проверки решения имени в адрес nslookup:
```bash
nslookup  hostname.example.com
```
Пример ожидаемого вывода:
```bash
Server:         10.224.151.215
Address:        10.224.151.215#53

Name:   hostname.example.com
Address: 192.168.1.100
```

## Диагностика прослушивания порта 53
```bash
sudo netstat -tulpn | grep :53

# Output example
tcp        0      0 127.0.0.1:53            0.0.0.0:*               LISTEN      2900395/dnsmasq
tcp6       0      0 ::1:53                  :::*                    LISTEN      2900395/dnsmasq
udp        0      0 0.0.0.0:5353            0.0.0.0:*                           750/avahi-daemon: r
udp        0      0 127.0.0.1:53            0.0.0.0:*                           2900395/dnsmasq
udp6       0      0 :::5353                 :::*                                750/avahi-daemon: r
udp6       0      0 ::1:53                  :::*                                2900395/dnsmasq
```

## Частые проблемы и решения

- Порт 53 занят другим сервисом
  ```bash
  Error starting userland proxy: listen udp4 0.0.0.0:53: bind: address already in use
  ```
  Варианты решения:
  - Остановить службы использующие порт 53
  ```bash
  #Ubuntu/Debian (systemd-resolved):
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved

  #CentOS/RHEL (NetworkManager):
  sudo systemctl stop NetworkManager
  sudo systemctl disable NetworkManager
  ```
  - Остановить процессы DNS
  ```bash
  sudo systemctl | grep "dns"
  sudo systemctl stop $id
  ```

## Автоматическое развертывание DNS (dnsmasq server):
```bash
# To start server
export CONTAINER_ENGINE=podman
dns_server_ip="10.0.0.100"
dns_clients_ips_list="192.168.1.10,192.168.1.11"
bash ./deploy_dnsmasq_in_container.sh --ips $dns_clients_ips_list --dns $dns_server_ip start

# To stop
bash ./deploy_dnsmasq_in_container.sh stop
```

## Примечания
Если в **resolv.conf** первый из списка серверов достуен, то поиск DNS записи будет осуществлен только на нем, остальные серверы будут проигнорированы.
