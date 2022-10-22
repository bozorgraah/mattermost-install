#!/bin/bash
set -eu
set -o pipefail

source ./header.sh
source ./functions.sh

read -p "Which mattermost version do you want to install? (default: 7.4.0): " version
version=${version:-7.4.0}
validate_version $version
read -p "Enter your database user (default: mmuser): " dbuser
dbuser=${dbuser:-mmuser}
validate_alphanum $dbuser
read -p "Enter your database password. only alphanum and underscore allowed (default: mmuser_password): " dbpass
dbpass=${dbpass:-mmuser_password}
validate_password $dbpass
read -p "Enter your database name (default: mattermost): " dbname
dbname=${dbname:-mattermost}
validate_alphanum $dbname
read -p "Enter your domain name (example.com): " domain
validate_domain $domain

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
wget https://releases.mattermost.com/$version/mattermost-$version-linux-amd64.tar.gz

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
sudo sed -i 's~"SiteURL": ""~"SiteURL": "https:\/\/'"$domain"'"~g' /opt/mattermost/config/config.json

# create systemd service
config_mattermost_service "postgresql"

print_message "creating nginx config file..."
config_mattermost_nginx "$domain"

print_message "restarting nginx and starting mattermost service..."
sudo systemctl restart nginx
sudo systemctl start mattermost

print_message "securing your domain..." "installing certbot..."
install_certbot
sudo certbot --nginx -d $domain

print_message "restarting mattermost..."
sudo systemctl restart mattermost

echo "##################################################################"
echo "##################################################################"
echo "Congrats! Mattermost is installed and ready to be used on your domain: $domain"
echo "##################################################################"
echo "##################################################################"
