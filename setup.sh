#!/bin/bash

# Atualizar o sistema
dnf update -y

# Instalar dependências necessárias
dnf install -y yum-utils device-mapper-persistent-data lvm2

# Alterar o hostname para srv_almasistemas.
 hostnamectl set-hostname srv_almasistemas

# Atualizar o arquivo /etc/hosts.
echo "127.0.1.1 srv_almasistemas" |  tee -a /etc/hosts > /dev/null

# Configurar IP fixo no arquivo de configuração do Netplan.
#INTERFACE_NAME="enp0s3" # Substitua pelo nome da sua interface de rede.
#NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

#cat <<EOL |  tee $NETPLAN_FILE > /dev/null 
#network:
#  version: 2
#  ethernets:
#    $INTERFACE_NAME:
#      dhcp4: no
#      addresses:
#        - 192.168.2.35/24 # Defina seu IP fixo aqui.
#      gateway4: 192.168.1.254 # Defina seu gateway padrão.
#      nameservers:
#        addresses:
#          - 8.8.8.8 # Google DNS.
#          - 8.8.4.4 # Google DNS.

# Aplicar as configurações do Netplan.
# netplan apply

# Adicionar repositório do Docker
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# Instalar o Docker
dnf install -y docker-ce docker-ce-cli containerd.io

# Iniciar e habilitar o serviço do Docker
systemctl start docker
systemctl enable docker

# Instalar o Docker Compose
dnf install pip
pip install docker-compose

# Criar diretório para o sistema
mkdir -p /sistema

# Criar arquivo docker-compose.yml para os serviços com volumes atribuídos a todos os sistemas
cat <<EOL > /sistema/docker-compose.yml
version: '3.8'

services:
  mysql:
    image: mysql:latest
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: zabbixdb
    volumes:
      - /sistema/mysql_data:/var/lib/mysql

  postgresql-server:
    image: postgres:latest
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - /sistema/postgresql_data:/var/lib/postgresql/data

  zabbix-server:
    image: zabbix/zabbix-server-pgsql:latest
    restart: unless-stopped
    depends_on:
      - postgresql-server
    environment:
      DB_SERVER_HOST: postgresql-server
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    ports:
      - "10051:10051"
    volumes:
      - /sistema/zabbix_server_data:/var/lib/zabbix

  zabbix-web-nginx-pgsql:
    image: zabbix/zabbix-web-nginx-pgsql:latest
    restart: unless-stopped
    depends_on:
      - postgresql-server
      - zabbix-server
    environment:
      DB_SERVER_HOST: postgresql-server
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
      ZBX_SERVER_HOST: zabbix-server
      PHP_TZ: \${PHP_TZ}
    ports:
      - "\${ZABBIX_FRONTEND_PORT}:8080"
    volumes:
      - /sistema/zabbix_web_data:/usr/share/zabbix

  zabbix-agent:
    image: zabbix/zabbix-agent:latest
    restart: unless-stopped
    depends_on:
      - zabbix-server
    environment:
      ZBX_HOSTNAME: "zabbix-server"
      ZBX_SERVER_HOST: zabbix-server
      ZBX_SERVER_PORT: '10051'
      ZBX_SERVER_ACTIVE: zabbix-server
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_INSTALL_PLUGINS: grafana-clock-panel
      GF_SECURITY_ADMIN_PASSWORD: adminpassword
    volumes:
      - /sistema/grafana_data:/var/lib/grafana

  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
    volumes:
      - /sistema/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - /sistema/prometheus_data:/prometheus

  node-exporter:
    image: quay.io/prometheus/node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro

  alertmanager:
    image: prom/alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml

  postgres:
    image: postgres:latest
    restart: always
    environment:
      POSTGRES_USER: netbox_user
      POSTGRES_PASSWORD: netbox_password
      POSTGRES_DB: netbox
    volumes:
      - /sistema/postgres_data:/var/lib/postgresql/data

  netbox:
    image: netboxcommunity/netbox:v2.11.5 
    restart: always 
    environment:
        NETBOX_SECRET_KEY="Argos@2024"
        DATABASE_URL="postgres://netbox_user:netbox_password@postgres/netbox"
    
  nginx-proxy-manager:
     image: jc21/nginx-proxy-manager 
     restart=unless-stopped 
     ports= 
       '80=80' # Public HTTP Port 
       '443=443' # Public HTTPS Port 
       '81=81' # Admin Web Port 
     volumes= 
       '/sistema/nginx/data=/data' 
       '/sistema/letsencrypt=/etc/letsencrypt'

volumes:
  mysql_data:
  postgresql_data:
  zabbix_server_data:
  zabbix_web_data:
  grafana_data:
  prometheus_data:

EOL

# Criar o arquivo .env
cat <<EOL > /sistema/.env
POSTGRES_USER=zabbix
POSTGRES_PASSWORD=strongpassword
POSTGRES_DB=zabbix
PHP_TZ=Europe/London
ZABBIX_FRONTEND_PORT=8080
EOL

# Criar o arquivo prometheus.yml
cat <<EOL > /sistema/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
EOL

# Iniciar os containers com Docker Compose no diretório correto para Nginx Proxy Manager e outros serviços.
cd /sistema &&  docker-compose up -d

echo "Instalação completa! O hostname foi alterado para srv_almasistemas e o IP fixo foi configurado."
echo "Instalação completa! Os serviços estão rodando."