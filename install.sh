#!/bin/bash

################################################################################
# Script for installing Nginx RTMP module
# Author: Henry Robert Muwanika
#-------------------------------------------------------------------------------
#
# Place this content in it and then make the file executable:
# sudo chmod +x install.sh
################################################################################

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
sudo apt install -y ffmpeg libav-tools x264 x265
ffmpeg -version

# Install nginx dependencies
sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev unzip git

sudo mkdir ~/build && cd ~/build

# Clone nginx-rtmp-module
git clone https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

# Download nginx
sudo wget http://nginx.org/download/nginx-1.19.6.tar.gz
sudo tar xzf nginx-1.19.6.tar.gz
cd nginx-1.19.6

# Build nginx with nginx-rtmp
sudo ./configure --with-http_ssl_module --with-http_stub_status_module --with-file-aio --add-module=../nginx-rtmp-module
sudo make 
sudo make install

# Start nginx server
sudo /usr/local/nginx/sbin/nginx

# Setup live streaming
sudo echo "" > /usr/local/nginx/conf/nginx.conf
sudo cat <<EOF > /usr/local/nginx/conf/nginx.conf

#############################################################################

#user  nobody;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

pid   /var/run/nginx.pid;

events {
    worker_connections  1024;
}

# RTMP configuration
rtmp {
    server {
        listen 1935;         # Listen on standard RTMP port
        chunk_size 4000;

        application stream {
            live on;
            # pull rtmp://origin-rtmp-server:1935/live name=m3tv static; 
            
            # Turn on HLS
            hls on;
            hls_path /usr/local/nginx/html/stream/hls;
            hls_fragment 3;
            hls_playlist_length 20;
	    hls_fragment_naming system;
            
            # MPEG-DASH is similar to HLS
            dash on;
            dash_path /usr/local/nginx/html/stream/dash;
            dash_fragment 5s;
            dash_playlist_length 30s;
                
            # disable consuming the stream from nginx as rtmp
            deny play all;
        }
    }
}
            
http  {
                sendfile on;
                tcp_nopush on;
                aio on;
                directio 512;
    
                keepalive_timeout  65;
    
                include mime.types;
                default_type application/octet-stream;

    server {
                listen 443;
                server_name example.com;
		       
		# Serve HLS fragments
		location /hls {
			types {
				application/vnd.apple.mpegurl m3u8;
				video/mp2t ts;
			}
			
			root /usr/local/nginx/html/stream;
            
                        # Disable cache
                        add_header Cache-Control no-cache; 
			add_header Access-Control-Allow-Origin *;       
		      }
		
                 # Serve DASH fragments
                 location /dash {
                          types {
                                  application/dash+xml mpd;
                                  video/mp4 mp4;
                       }

		        root /usr/local/nginx/html/stream;
            
		        # Disable cache
		        add_header Cache-Control no-cache; 
		        add_header Access-Control-Allow-Origin *;
                        }		
		
		        # This URL provides RTMP statistics in XML
		        location /stat {
			                rtmp_stat all;
			                rtmp_stat_stylesheet stat.xsl; 
		        }

		        location /stat.xsl {
			               # XML stylesheet to view RTMP stats.
                                       # Copy stat.xsl wherever you want
                                       # and put the full directory path here
			               root /usr/local/nginx/html;
		        } 
	          }
           }

################################################################################################################
EOF

mkdir /usr/local/nginx/html/stream
mkdir /usr/local/nginx/html/stream/hls
mkdir /usr/local/nginx/html/stream/dash

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

###### Install SSL Certificates #########
sudo apt install software-properties-common -y
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx -d vps.rw --noninteractive --agree-tos --email hrmuwanika@gmail.com --redirect
sudo systemctl reload nginx
 
