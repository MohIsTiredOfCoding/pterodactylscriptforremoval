#!/bin/bash
# Full removal of Pterodactyl, Wings, MySQL, Docker, Certbot, Nginx, Apache
# Keeps Cloudflared
# Re-adds Certbot repo and reinstalls fresh

MYSQL_PASS="jinqo"

echo ">>> Stopping services..."
systemctl stop pteroq wings mysql mariadb nginx apache2 2>/dev/null
systemctl disable pteroq wings mysql mariadb nginx apache2 2>/dev/null

echo ">>> Removing systemd service files..."
rm -f /etc/systemd/system/pteroq.service
rm -f /etc/systemd/system/wings.service
systemctl daemon-reload

echo ">>> Removing Pterodactyl panel files..."
rm -rf /var/www/pterodactyl

echo ">>> Removing Wings files..."
rm -rf /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl

echo ">>> Removing ALL Certbot/Let's Encrypt certificates..."
rm -rf /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt

echo ">>> Removing Certbot and its repositories..."
apt-get purge -y certbot python3-certbot* 2>/dev/null
add-apt-repository -y --remove ppa:certbot/certbot 2>/dev/null

echo ">>> Dropping Pterodactyl database and user..."
mysql -u root -p$MYSQL_PASS -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null
mysql -u root -p$MYSQL_PASS -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null
mysql -u root -p$MYSQL_PASS -e "DROP USER IF EXISTS 'pterodactyl'@'localhost';" 2>/dev/null
mysql -u root -p$MYSQL_PASS -e "FLUSH PRIVILEGES;" 2>/dev/null

echo ">>> Removing user/group pterodactyl..."
userdel -r pterodactyl 2>/dev/null
groupdel pterodactyl 2>/dev/null

echo ">>> Cleaning up Docker completely..."
docker stop $(docker ps -aq) 2>/dev/null
docker rm -f $(docker ps -aq) 2>/dev/null
docker rmi -f $(docker images -q) 2>/dev/null
docker volume rm $(docker volume ls -q) 2>/dev/null
docker network prune -f 2>/dev/null
docker system prune -a --volumes -f 2>/dev/null
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras 2>/dev/null
apt-get autoremove -y
rm -rf /var/lib/docker /etc/docker

echo ">>> Uninstalling MySQL/MariaDB completely..."
apt-get purge -y mysql-server mysql-client mariadb-server mariadb-client 2>/dev/null
apt-get autoremove -y
rm -rf /var/lib/mysql /etc/mysql

echo ">>> Purging Nginx and Apache completely..."
apt-get purge -y nginx nginx-common nginx-full apache2 apache2-bin apache2-utils 2>/dev/null
apt-get autoremove -y
rm -rf /etc/nginx /var/log/nginx /var/www/html
rm -rf /etc/apache2 /var/log/apache2

echo ">>> Re-adding official Certbot repository..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y universe
add-apt-repository -y ppa:certbot/certbot
apt-get update

echo ">>> Installing fresh Certbot..."
apt-get install -y certbot python3-certbot-nginx python3-certbot-apache

echo ">>> ✅ Cleanup finished!"
echo "Pterodactyl, Wings, MySQL, Docker, Certbot, Nginx, and Apache removed."
echo "Cloudflared was NOT removed."
echo "Certbot repo has been re-added and Certbot reinstalled cleanly."
