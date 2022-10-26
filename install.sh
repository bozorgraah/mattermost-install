#!/bin/bash
set -eu
set -o pipefail

source ./header.sh
source ./functions.sh

# get input while not valid
while : ; do
  read -p "Which mattermost version do you want to install? (default: 7.4.0): " version
  version=${version:-7.4.0}
  validate_version $version && break
done

while : ; do
  read -p "Enter your database user (default: mmuser): " dbuser
  dbuser=${dbuser:-mmuser}
  validate_alphanum $dbuser && break
done

while : ; do
  read -p "Enter your database password. only alphanum and underscore allowed (default: mmuser_password): " dbpass
  dbpass=${dbpass:-mmuser_password}
  validate_password $dbpass && break
done

while : ; do
  read -p "Enter your database name (default: mattermost): " dbname
  dbname=${dbname:-mattermost}
  validate_alphanum $dbname && break
done

while : ; do
  read -p "Enter your domain name. Enter IP if you don't have a domain name (e.g. example.com or 10.10.10.10): " domain
  validate_domain $domain && break
done

print_message "Installing postgreSQL..."
install_postgresql

print_message "Installing nginx..."
install_nginx

# check if mattermost is installed
if [[ -d "/opt/mattermost" ]]; then
  remove_mattermost
fi

print_message "Installing mattermost..." "getting version $version binary file..."
cd ~
# check if file exists
if [[ -f "mattermost-$version-linux-amd64.tar.gz" ]]; then
  echo "File already exists."
  read -p "Do you want to remove the file and download again? (y/n) " dl_again
  if [[ $dl_again == [yY] || $dl_again == [yY][eE][sS] ]]; then
    rm mattermost-$version-linux-amd64.tar.gz
    wget https://releases.mattermost.com/$version/mattermost-$version-linux-amd64.tar.gz
  fi
else
  wget https://releases.mattermost.com/$version/mattermost-$version-linux-amd64.tar.gz
fi

print_message "extracting..."
tar -xvzf mattermost*.gz
sudo cp -r mattermost /opt
sudo mkdir /opt/mattermost/data

print_message "creating mattermost user group and assigning permissions..."
# check if mattermost user exists
if id -u mattermost >/dev/null 2>&1; then
  echo "Mattermost user already exists!"
else
  sudo useradd --system --user-group mattermost
fi
sudo chown -R mattermost:mattermost /opt/mattermost
sudo chmod -R g+w /opt/mattermost

print_message "setting up database..." 
echo "if you get an error here, please resolve it manually and run the script again."
sudo -i -u postgres -H -- psql -c "DROP DATABASE IF EXISTS $dbname;"
sudo -i -u postgres -H -- psql -c "CREATE DATABASE $dbname;"
sudo -i -u postgres -H -- psql -c "DROP USER IF EXISTS $dbuser;"
sudo -i -u postgres -H -- psql -c "CREATE USER $dbuser WITH PASSWORD '$dbpass';"
sudo -i -u postgres -H -- psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $dbuser;"

print_message "configuring mattermost..."
# config postgres database
sudo sed -i -e 's~"DataSource": ".*"~"DataSource": "postgres://'"$dbuser"':'"$dbpass"'@localhost:5432/'"$dbname"'?sslmode=disable\&connect_timeout=10\&binary_parameters=yes"~g' /opt/mattermost/config/config.json
# enable plugin uploads
sudo sed -i 's~"EnableUploads": false~"EnableUploads": true~g' /opt/mattermost/config/config.json
# enter site url
sudo sed -i 's~"SiteURL": ""~"SiteURL": "http:\/\/'"$domain"'"~g' /opt/mattermost/config/config.json

# create systemd service
config_mattermost_service "postgresql"

print_message "creating nginx config file..."
config_mattermost_nginx "$domain"

print_message "restarting nginx..."
sudo systemctl restart nginx
echo "nginx restarted!"

if ! is_ip "$domain"; then
  read -p "Do you want to enable SSL (https)? (y/n) (default: y): " enable_ssl
  enable_ssl=${enable_ssl:-y}
  if [[ $enable_ssl == [yY] || $enable_ssl == [yY][eE][sS] ]]; then
    print_message "securing your domain..." "installing certbot..."
    install_certbot
    sudo certbot --nginx -d $domain
    sudo sed -i 's~http:\/\/'"$domain"'~https:\/\/'"$domain"'~g' /opt/mattermost/config/config.json
  fi
fi

print_message "starting mattermost..." "this may take a while... up to several minutes..."
sudo systemctl start mattermost

echo "##################################################################"
echo "##################################################################"
echo "Congrats! Mattermost is installed and ready to be used on your domain: $domain"
echo "##################################################################"
echo "##################################################################"
