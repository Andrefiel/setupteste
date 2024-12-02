#!/bin/bash

# Atualiza o sistema
dnf update -y

# Altera o hostname
hostnamectl set-hostname srv-almaserver

# Instala o EPEL e outras dependências
dnf install epel-release -y

# Instala o Nginx
dnf install nginx -y
systemctl start nginx
systemctl enable nginx

# Instala o Certbot para Nginx
dnf install certbot python3-certbot-nginx -y

# Configura o firewall para Nginx
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Instala o MySQL
dnf install @mysql -y
systemctl start mysqld
systemctl enable mysqld

# Instala o PostgreSQL
dnf install postgresql-server postgresql-contrib -y
postgresql-setup initdb
systemctl start postgresql
systemctl enable postgresql

# Instala o Redis para NetBox
dnf install redis -y
systemctl start redis
systemctl enable redis

# Instala o Zabbix
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/9/x86_64/zabbix-release-7.0-1.el9.noarch.rpm
dnf clean all
dnf install zabbix-server-mysql zabbix-web-mysql zabbix-agent -y

# Configura o banco de dados do Zabbix (MySQL)
mysql -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'senha_forte';"
mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Importa o esquema do banco de dados do Zabbix
zcat /usr/share/doc/zabbix-server-mysql*/schema.sql.gz | mysql -uzabbix -p zabbix

# Configura o Zabbix Server e Agent
sed -i 's/^DBPassword=.*/DBPassword=senha_forte/' /etc/zabbix/zabbix_server.conf
echo "Server=127.0.0.1" >> /etc/zabbix/zabbix_agentd.conf
echo "Hostname=srv-almaserver" >> /etc/zabbix/zabbix_agentd.conf

# Inicia os serviços do Zabbix Server e Agent
systemctl start zabbix-server zabbix-agent
systemctl enable zabbix-server zabbix-agent

# Instala o Grafana
dnf install https://dl.grafana.com/oss/release/grafana-release.rpm -y
dnf install grafana -y
systemctl start grafana-server
systemctl enable grafana-server

# Instala o GLPI (gerenciador de ativos)
dnf install glpi glpi-plugins glpi-docs -y

# Instalação do NetBox
dnf install python3 python3-pip python3-venv python3-dev gcc libpq-dev libffi-dev libxml2-dev libxslt1-dev zlib1g-dev -y

# Cria um diretório para o NetBox e faz download da versão mais recente do NetBox.
mkdir /opt/netbox && cd /opt/netbox/
git clone https://github.com/netbox-community/netbox.git .
pip3 install -r requirements.txt

# Configuração do banco de dados para NetBox (PostgreSQL)
sudo -u postgres psql <<EOF
CREATE DATABASE netboxdb;
CREATE USER netboxuser WITH PASSWORD 'senha_forte';
GRANT ALL PRIVILEGES ON DATABASE netboxdb TO netboxuser;
EOF

# Copia e edita a configuração do NetBox.
cp netbox/configuration_example.py netbox/configuration.py
sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['srv-almaserver']/" netbox/configuration.py
sed -i "s/^DATABASE = .*/DATABASE = {\n    'NAME': 'netboxdb',\n    'USER': 'netboxuser',\n    'PASSWORD': 'senha_forte',\n    'HOST': 'localhost',\n    'PORT': '',\n}/" netbox/configuration.py

# Gera a chave secreta.
SECRET_KEY=$(python3 netbox/generate_secret_key.py)
sed -i "s/^SECRET_KEY = .*/SECRET_KEY = '${SECRET_KEY}'/" netbox/configuration.py

# Executa as migrações do banco de dados.
python3 netbox/manage.py migrate

# Cria um super usuário para acesso ao NetBox.
python3 netbox/manage.py createsuperuser --username admin --email admin@srv-almaserver.com

# Configuração de portas para evitar conflitos e gerenciar hosts pelo Nginx.
cat <<EOL > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name srv-almaserver;

    location / {
        proxy_pass http://localhost:3000;  # Grafana na porta 3000.
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 8080;  # Zabbix Web na porta 8080.
    server_name srv-almaserver;

    location / {
        proxy_pass http://localhost:80;  # Redireciona para a interface web do Zabbix.
    }
}

server {
    listen 9090;  # GLPI na porta 9090.
    server_name srv-almaserver;

    location / {
        proxy_pass http://localhost:80;  # Redireciona para a interface web do GLPI.
    }
}

server {
    listen 8001;  # NetBox na porta 8001.
    server_name srv-almaserver;

    location / {
        proxy_pass http://127.0.0.1:8001;  # Redireciona para a interface web do NetBox.
    }
}
EOL

# Testa a configuração do Nginx e reinicia o serviço se não houver erros.
nginx -t && systemctl restart nginx

echo "Instalação concluída! Acesse os serviços em suas respectivas portas."

# Exibe as portas de acesso aos sistemas instalados:
echo "Portas de acesso:"
echo "Zabbix Web: 8080"
echo "Grafana: 3000"
echo "GLPI: 9090"
echo "NetBox: 8001"