#!/bin/bash
set -eu
set -o pipefail

# function to get a message as input and print it to the screen
print_message() {
  echo -e ""
  echo "========================================"
  for i in "$@"
  do
    echo "$i"
  done
  echo "========================================"
  echo -e ""
}

source ./header.sh

read -p "enter your database user (default: mmuser): " dbuser
dbuser=${dbuser:-mmuser}
read -p "enter your database password (default: mmuser_password): " dbpass
dbpass=${dbpass:-mmuser_password}
read -p "enter your database name (default: mattermost): " dbname
dbname=${dbname:-mattermost}
read -p "enter your domain name (example.com): " domain

print_message "Installing postgreSQL..."
# check if postgreSQL is installed
if [ -x "$(command -v psql)" ]; then
  echo "PostgreSQL is already installed!"
else
  sudo apt update
  sudo apt install postgresql postgresql-contrib -y
  sudo systemctl start postgresql.service
fi

print_message "Installing nginx..."
# check if nginx is installed
if [ -x "$(command -v nginx)" ]; then
  echo "Nginx is already installed!"
else
  sudo apt update
  sudo apt install nginx -y
  
  sudo ufw allow 'Nginx HTTP'
  sudo ufw allow 'Nginx HTTPS'
  sudo ufw allow 22/tcp 
  sudo ufw enable
fi

print_message "Installing mattermost..." "getting version 7.4 binary file..."
cd ~
wget https://releases.mattermost.com/7.4.0/mattermost-7.4.0-linux-amd64.tar.gz
print_message "extracting..."
tar -xvzf mattermost*.gz
sudo cp -r mattermost /opt
sudo mkdir /opt/mattermost/data
print_message "creating mattermost user group and assigning permissions..."
sudo useradd --system --user-group mattermost
sudo chown -R mattermost:mattermost /opt/mattermost
sudo chmod -R g+w /opt/mattermost


print_message "setting up database..." 
sudo -i -u postgres -H -- psql -c "CREATE DATABASE $dbname;"
sudo -i -u postgres -H -- psql -c "CREATE USER $dbuser WITH PASSWORD '$dbpass';"
sudo -i -u postgres -H -- psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $dbuser;"
sudo systemctl reload postgresql

print_message "configuring mattermost..."
# config postgres database
sed -i -e 's~"DataSource": ".*"~"DataSource": "postgres://'"$dbuser"':'"$dbpass"'@localhost:5432/'"$dbname"'?sslmode=disable\&connect_timeout=10\&binary_parameters=yes"~g' /opt/mattermost/config/config.json
# enable plugin uploads
sed -i 's~"EnableUploads": false~"EnableUploads": true~g' /opt/mattermost/config/config.json
# enter site url
sed -i 's~"SiteURL": ""~"SiteURL": "https:\/\/'"$domain"'"~g' /opt/mattermost/config/config.json

# create mattermost system service
echo "[Unit]
Description=Mattermost
After=network.target
After=postgresql.service
Requires=postgresql.service

[Service]
Type=notify
User=mattermost
Group=mattermost
ExecStart=/opt/mattermost/bin/mattermost
TimeoutStartSec=3600
Restart=always
RestartSec=10
WorkingDirectory=/opt/mattermost
LimitNOFILE=49152

[Install]
WantedBy=postgresql.service" > /etc/systemd/system/mattermost.service

sudo systemctl daemon-reload
sudo systemctl enable mattermost

print_message "creating nginx config file..."
echo "upstream backend {
   server localhost:8065;
   keepalive 32;
}

proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=mattermost_cache:10m max_size=3g inactive=120m use_temp_path=off;

server {
   listen 80;
   server_name $domain;

   location ~ /api/v[0-9]+/(users/)?websocket$ {
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection \"upgrade\";
       client_max_body_size 50M;
       proxy_set_header Host \$http_host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;
       proxy_set_header X-Frame-Options SAMEORIGIN;
       proxy_buffers 256 16k;
       proxy_buffer_size 16k;
       client_body_timeout 60;
       send_timeout 300;
       lingering_timeout 5;
       proxy_connect_timeout 90;
       proxy_send_timeout 300;
       proxy_read_timeout 90s;
       proxy_pass http://backend;
   }

   location / {
       client_max_body_size 50M;
       proxy_set_header Connection \"\";
       proxy_set_header Host \$http_host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;
       proxy_set_header X-Frame-Options SAMEORIGIN;
       proxy_buffers 256 16k;
       proxy_buffer_size 16k;
       proxy_read_timeout 600s;
       proxy_cache mattermost_cache;
       proxy_cache_revalidate on;
       proxy_cache_min_uses 2;
       proxy_cache_use_stale timeout;
       proxy_cache_lock on;
       proxy_http_version 1.1;
       proxy_pass http://backend;
   }
}" > /etc/nginx/sites-available/mattermost.conf
sudo ln -s /etc/nginx/sites-available/mattermost.conf /etc/nginx/sites-enabled/mattermost.conf
# check nginx config
sudo nginx -t
print_message "restarting nginx and starting mattermost service..."
sudo systemctl restart nginx
sudo systemctl start mattermost

print_message "securing your domain..." "installing certbot..."
# check if certbot is installed
if [ -x "$(command -v certbot)" ]; then
  echo "Certbot is already installed!"
else
  sudo apt install python3-certbot-nginx -y
fi
sudo certbot --nginx -d $domain

print_message "restarting mattermost..."
sudo systemctl restart mattermost

echo "##################################################################"
echo "##################################################################"
echo "Congrats! Mattermost is installed and ready to be used on your domain: $domain"
echo "##################################################################"
echo "##################################################################"
