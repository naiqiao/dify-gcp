#!/bin/bash

# Startup script for Dify GCP instance
# This script prepares the instance for Dify deployment

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    wget

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install Docker Compose (standalone)
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create docker group and add user
groupadd -f docker
usermod -aG docker $USER

# Install Google Cloud SQL Proxy
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O /usr/local/bin/cloud_sql_proxy
chmod +x /usr/local/bin/cloud_sql_proxy

# Install Nginx for reverse proxy
apt-get install -y nginx

# Install Certbot for SSL certificates
apt-get install -y certbot python3-certbot-nginx

# Create directories
mkdir -p /opt/dify
mkdir -p /var/log/dify
mkdir -p /etc/dify

# Set permissions
chown -R www-data:www-data /opt/dify
chown -R www-data:www-data /var/log/dify
chown -R www-data:www-data /etc/dify

# Create systemd service for Cloud SQL Proxy
cat > /etc/systemd/system/cloud-sql-proxy.service << 'EOF'
[Unit]
Description=Google Cloud SQL Proxy
After=network.target

[Service]
Type=simple
User=www-data
ExecStart=/usr/local/bin/cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable services
systemctl enable docker
systemctl enable nginx
systemctl enable cloud-sql-proxy

# Configure firewall (ufw)
ufw --force enable
ufw allow ssh
ufw allow http
ufw allow https

# Set up log rotation
cat > /etc/logrotate.d/dify << 'EOF'
/var/log/dify/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# Create health check script
cat > /opt/dify/health-check.sh << 'EOF'
#!/bin/bash
curl -f http://localhost/health || exit 1
EOF
chmod +x /opt/dify/health-check.sh

# Install monitoring tools
apt-get install -y htop iotop nethogs

# Set up automatic security updates
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# Configure kernel parameters for better performance
cat >> /etc/sysctl.conf << 'EOF'
# Dify performance optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
vm.swappiness = 1
EOF

sysctl -p

# Create maintenance scripts directory
mkdir -p /opt/dify/scripts

# Log completion
echo "$(date): Startup script completed successfully" >> /var/log/dify/startup.log 