#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to setup directories and permissions
setup_directories() {
    print_status "Setting up directories and permissions..."
    
    # Create necessary directories
    sudo mkdir -p /opt/dify
    sudo mkdir -p /var/log/dify
    sudo mkdir -p /etc/dify
    
    # Create volume directories for Docker Compose
    mkdir -p ~/docker-compose/volumes/app/storage
    mkdir -p ~/docker-compose/volumes/app/logs
    mkdir -p ~/docker-compose/volumes/nginx/logs
    mkdir -p ~/docker-compose/volumes/certbot/conf
    mkdir -p ~/docker-compose/volumes/certbot/www
    
    # Set proper permissions
    sudo chown -R $USER:$USER ~/docker-compose/volumes
    chmod -R 755 ~/docker-compose/volumes
    
    print_success "Directories setup completed!"
}

# Function to configure database connection
setup_database() {
    print_status "Setting up database connection..."
    
    # Load environment variables
    source ~/.env
    
    # Update Cloud SQL Proxy service with actual connection name
    sudo sed -i "s/CONNECTION_NAME/${DB_CONNECTION_NAME}/g" /etc/systemd/system/cloud-sql-proxy.service
    
    # Start Cloud SQL Proxy
    sudo systemctl daemon-reload
    sudo systemctl start cloud-sql-proxy
    sudo systemctl enable cloud-sql-proxy
    
    # Wait for proxy to be ready
    print_status "Waiting for Cloud SQL Proxy to be ready..."
    for i in {1..30}; do
        if nc -z localhost 5432; then
            print_success "Cloud SQL Proxy is ready!"
            break
        fi
        sleep 2
    done
    
    print_success "Database connection setup completed!"
}

# Function to configure Nginx
setup_nginx() {
    print_status "Setting up Nginx configuration..."
    
    # Load environment variables
    source ~/.env
    
    # Configure domain in Nginx config
    if [ -n "$DOMAIN" ]; then
        sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" ~/docker-compose/nginx/conf.d/dify.conf
        print_status "Nginx configured for domain: $DOMAIN"
    else
        # Configure for IP access
        EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
        sed -i "s/DOMAIN_PLACEHOLDER/${EXTERNAL_IP}/g" ~/docker-compose/nginx/conf.d/dify.conf
        print_status "Nginx configured for IP access: $EXTERNAL_IP"
    fi
    
    print_success "Nginx configuration completed!"
}

# Function to start Dify services
start_dify_services() {
    print_status "Starting Dify services..."
    
    cd ~/docker-compose
    
    # Pull latest images
    docker-compose pull
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 30
    
    # Check service health
    for i in {1..30}; do
        if docker-compose ps | grep -q "Up"; then
            print_success "Services are starting up!"
            break
        fi
        sleep 5
    done
    
    # Display service status
    docker-compose ps
    
    print_success "Dify services started successfully!"
}

# Function to run database migrations
run_database_migrations() {
    print_status "Running database migrations..."
    
    cd ~/docker-compose
    
    # Wait for API service to be ready
    sleep 60
    
    # Run database initialization
    docker-compose exec -T api python -m flask db upgrade
    
    print_success "Database migrations completed!"
}

# Function to setup monitoring
setup_monitoring() {
    print_status "Setting up monitoring and logging..."
    
    # Create monitoring script
    cat > ~/scripts/monitor-dify.sh << 'EOF'
#!/bin/bash

echo "=== Dify Service Status ==="
docker-compose ps

echo -e "\n=== Resource Usage ==="
docker stats --no-stream

echo -e "\n=== Recent Logs ==="
docker-compose logs --tail=50 api web worker

echo -e "\n=== Disk Usage ==="
df -h

echo -e "\n=== Memory Usage ==="
free -h
EOF
    
    chmod +x ~/scripts/monitor-dify.sh
    
    # Setup log rotation for Docker logs
    sudo tee /etc/logrotate.d/docker > /dev/null << 'EOF'
/var/lib/docker/containers/*/*-json.log {
    rotate 7
    daily
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 100M
}
EOF
    
    print_success "Monitoring setup completed!"
}

# Function to create backup script
create_backup_script() {
    print_status "Creating backup script..."
    
    cat > ~/scripts/backup-dify.sh << 'EOF'
#!/bin/bash

set -e

# Load environment variables
source ~/.env

BACKUP_DIR="/opt/dify/backups"
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="dify_backup_${DATE}.tar.gz"

# Create backup directory
sudo mkdir -p $BACKUP_DIR

# Backup application data
echo "Creating backup: $BACKUP_FILE"

# Stop services temporarily
docker-compose stop api worker

# Create database backup
docker-compose exec -T cloud-sql-proxy pg_dump -h localhost -U $DB_USERNAME -d $DB_DATABASE > /tmp/db_backup_${DATE}.sql

# Create full backup
sudo tar -czf $BACKUP_DIR/$BACKUP_FILE \
    -C ~/docker-compose volumes/ \
    -C /tmp db_backup_${DATE}.sql

# Restart services
docker-compose start api worker

# Upload to Google Storage (optional)
if [ -n "$GOOGLE_STORAGE_BUCKET_NAME" ]; then
    gsutil cp $BACKUP_DIR/$BACKUP_FILE gs://$GOOGLE_STORAGE_BUCKET_NAME/backups/
    echo "Backup uploaded to Google Storage"
fi

# Cleanup old backups (keep last 7 days)
sudo find $BACKUP_DIR -name "dify_backup_*.tar.gz" -mtime +7 -delete
rm -f /tmp/db_backup_${DATE}.sql

echo "Backup completed: $BACKUP_FILE"
EOF
    
    chmod +x ~/scripts/backup-dify.sh
    
    # Setup daily backup cron job
    (crontab -l 2>/dev/null; echo "0 2 * * * ~/scripts/backup-dify.sh") | crontab -
    
    print_success "Backup script created and scheduled!"
}

# Function to display final status
show_status() {
    print_success "🎉 Dify setup completed successfully!"
    echo ""
    echo "Service Status:"
    cd ~/docker-compose && docker-compose ps
    echo ""
    echo "Access Information:"
    
    # Load environment variables
    source ~/.env
    
    if [ -n "$DOMAIN" ]; then
        echo "  URL: http://$DOMAIN (HTTPS will be available after SSL setup)"
    else
        EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
        echo "  URL: http://$EXTERNAL_IP"
    fi
    
    echo ""
    echo "Management Scripts:"
    echo "  Monitor: ~/scripts/monitor-dify.sh"
    echo "  Backup: ~/scripts/backup-dify.sh"
    echo "  Update: ~/scripts/update-dify.sh"
    echo ""
    echo "Logs:"
    echo "  View logs: docker-compose logs -f"
    echo "  View specific service: docker-compose logs -f api"
}

# Main execution
main() {
    print_status "Starting Dify instance setup..."
    
    setup_directories
    setup_database
    setup_nginx
    start_dify_services
    run_database_migrations
    setup_monitoring
    create_backup_script
    show_status
    
    print_success "Dify instance setup completed!"
}

# Run main function
main 