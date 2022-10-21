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

install_nginx() {
  # check if nginx is installed
  if [ -x "$(command -v nginx)" ]; then
    echo "Nginx is already installed!"
  else
    sudo apt update
    sudo apt install nginx -y
    
    print_message "Enabling firewall and openning ports 80 and 443..."
    sudo ufw allow 'Nginx HTTP'
    sudo ufw allow 'Nginx HTTPS'
    sudo ufw allow 22/tcp 
    sudo ufw enable
  fi
}

install_postgresql() {
  # check if postgreSQL is installed
  if [ -x "$(command -v psql)" ]; then
    echo "PostgreSQL is already installed!"
  else
    sudo apt update
    sudo apt install postgresql postgresql-contrib -y
    sudo systemctl start postgresql.service
  fi
}

install_certbot() {
  # check if certbot is installed
  if [ -x "$(command -v certbot)" ]; then
    echo "Certbot is already installed!"
  else
    sudo apt install python3-certbot-nginx -y
  fi
}

remove_mattermost() {
  print_message "Removing previously istalled Mattermost server..."
  read -p "Do you want to remove the previously installed Mattermost? (y/n): " remove

  if [[ "$remove" == [yY] || "$remove" == [yY][eE][sS] ]]; then
    sudo systemctl stop mattermost.service
    sudo systemctl disable mattermost.service
    [[ -d /opt/mattermost ]] && sudo rm -rf /opt/mattermost
    [[ -d /var/log/mattermost ]] && sudo rm -rf /var/log/mattermost
    [[ -d /var/mattermost ]] && sudo rm -rf /var/mattermost
    [[ -d /etc/mattermost ]] && sudo rm -rf /etc/mattermost
    [[ -d /etc/systemd/system/mattermost.service ]] && sudo rm -rf /etc/systemd/system/mattermost.service
    sudo rm -rf /etc/systemd/system/mattermost.service
    # remove nginx config 
    sudo rm -rf /etc/nginx/sites-available/mattermost.conf
    sudo rm -rf /etc/nginx/sites-enabled/mattermost.conf
    sudo systemctl restart nginx
  else
    print_message "Mattermost is already installed!"
    exit 1
  fi
}

config_mattermost_service() {
  echo "[Unit]
  Description=Mattermost
  After=network.target
  After=$1.service
  Requires=$1.service

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
  WantedBy=$1.service" > /etc/systemd/system/mattermost.service

  sudo systemctl daemon-reload
  sudo systemctl enable mattermost
}


config_mattermost_nginx() {
  echo "upstream backend {
     server localhost:8065;
     keepalive 32;
  }

  proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=mattermost_cache:10m max_size=3g inactive=120m use_temp_path=off;

  server {
     listen 80;
     server_name $1;

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

  if [[ -f /etc/nginx/sites-enabled/mattermost.conf ]]; then
    sudo rm -rf /etc/nginx/sites-enabled/mattermost.conf
  fi
  sudo ln -s /etc/nginx/sites-available/mattermost.conf /etc/nginx/sites-enabled/mattermost.conf
  # check nginx config
  sudo nginx -t
}



