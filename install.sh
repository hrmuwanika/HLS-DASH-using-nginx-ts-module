#!/bin/bash

################################################################################
# Script for installing Nginx TS module
# Author: Henry Robert Muwanika
#-------------------------------------------------------------------------------
#
# Place this content in it and then make the file executable:
# sudo chmod +x install.sh
################################################################################

# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
# Set the website name
WEBSITE_NAME="example.com"

#----------------------------------------------------
# Disable password authentication
#----------------------------------------------------
sudo sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config 
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo service sshd restart

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n============== Update Server ======================="
sudo apt update 
sudo apt upgrade -y
sudo apt autoremove -y

# Install FFMPEG
sudo add-apt-repository ppa:jonathonf/ffmpeg-4
sudo apt update
sudo apt install -y ffmpeg x264 x265

# Install nginx dependencies
sudo apt install -y autoconf automake build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev unzip git

sudo mkdir ~/build && cd ~/build

# Clone nginx-ts-module
git clone https://github.com/arut/nginx-ts-module.git

# Clone nginx-rtmp-module
git clone https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

# Download nginx
sudo wget http://nginx.org/download/nginx-1.19.6.tar.gz
sudo tar xzf nginx-1.19.6.tar.gz
cd nginx-1.19.6

# Build nginx with nginx-rtmp
sudo ./configure --with-http_ssl_module --with-http_stub_status_module --add-module=../nginx-ts-module --add-module=../nginx-rtmp-module
sudo make 
sudo make install

# Start nginx server
sudo /usr/local/nginx/sbin/nginx

# Setup live streaming
sudo echo "" > /usr/local/nginx/conf/nginx.conf
sudo cat <<EOF > /usr/local/nginx/conf/nginx.conf

#############################################################################

#user  nobody;
worker_processes auto;

pid   /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
         include  mime.types;
         default_type  application/octet-stream;

         sendfile    on;
         tcp_nopush  on;
         tcp_nodelay on;

         keepalive_timeout  65;
         
    server {
        listen 8080;
        server_name  $WEBSITE_NAME;

        location / {
            # Here we can put our website
            root   /var/www/html;
            index  index.html index.htm;
        }

        location /publish/ {
            ts;
            ts_hls path=/var/media/hls segment=2s;
            ts_dash path=/var/media/dash segment=2s;
            
            # This directive sets unlimited request body size
            client_max_body_size 0;
        }

        location /play/ {
            types {
                application/x-mpegURL m3u8;
                application/dash+xml mpd;
                video/MP2T ts;
                video/mp4 mp4;
            }
            
            # Where the media(hls or dash) files are located
            alias /var/media/;
        }
    }
}

################################################################################################################
EOF

mkdir /var/media
mkdir /var/media/hls
mkdir /var/media/dash

# Create Nginx systemd daemon
sudo cat <<EOF > /lib/systemd/system/nginx.service

[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/usr/local/nginx/sbin/nginx -s reload -c /usr/local/nginx/conf/nginx.conf
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target

EOF

sudo systemctl daemon-reload
sudo systemctl enable nginx.service
sudo systemctl restart nginx.service

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ]  && [ $WEBSITE_NAME != "example.com" ];then
  sudo apt-get remove certbot
  sudo snap install core
  sudo snap refresh core
  sudo snap install --classic certbot
  sudo ln -s /snap/bin/certbot /usr/bin/certbot
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo systemctl reload nginx  
  echo "\n============ SSL/HTTPS is enabled! ========================"
else
  echo "\n==== SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration! ======"
fi

sudo systemctl status nginx 


 
