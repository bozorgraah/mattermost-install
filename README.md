# Mattermost Installation Script

This script is for those who want to do the Mattermost manual installation, automated and faster without encountering error logs.
Mattermost has its installation script, but it can't be used efficiently due to heavy restrictions on servers in Iran. 
This script does everything as if you were doing it manually and it does not need you to set up a proxy or DNS to be able to use it.

## How it works
It works based on the [official Mattermost documentation](https://docs.mattermost.com/install/installing-ubuntu-2004-LTS.html) and gets some help from the [Digital Ocean blog](https://www.digitalocean.com/community/tutorials/how-to-set-up-mattermost-on-ubuntu-20-04) on how to install Mattermost on an ubuntu server.
I used PostgreSQL as the database and Nginx as the web server through this script.

## Usage
In order to use this script simply clone this repository and run the install script:
```sh
git clone https://github.com/m-salehi-v/mattermost
cd mattermost
bash install.sh
```
First you have to answer some simple question and the script will do the rest.
Also if you want SSL certificate you need to answer certbot questions at the end of the script.
