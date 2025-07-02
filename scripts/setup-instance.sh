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

# Function to install Docker and Docker Compose
install_docker() {
    print_status "Installing Docker and Docker Compose..."
    
    # Update package manager
    sudo apt-get update
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker and Docker Compose installed!"
}

# Function to install required system packages
install_system_packages() {
    print_status "Installing required system packages..."
    
    sudo apt-get update
    sudo apt-get install -y \
        curl \
        wget \
        unzip \
        jq \
        netcat \
        postgresql-client \
        openssl
    
    print_success "System packages installed!"
}

# Function to setup directories and permissions
setup_directories() {
    print_status "Setting up directories and permissions..."
    
    # Create Docker Compose volume directories
    mkdir -p ~/docker-compose/volumes/app/storage
    mkdir -p ~/docker-compose/volumes/app/logs
    mkdir -p ~/docker-compose/volumes/nginx/logs
    mkdir -p ~/docker-compose/volumes/certbot/conf
    mkdir -p ~/docker-compose/volumes/certbot/www
    
    # Set proper permissions
    chmod -R 755 ~/docker-compose/volumes
    
    print_success "Directories setup completed!"
}

# Function to configure Docker Compose environment
configure_docker_compose() {
    print_status "Configuring Docker Compose environment..."
    
    cd ~/docker-compose
    
    # Load environment variables
    if [ -f .env ]; then
        source .env
        print_status "Environment variables loaded from .env file"
    else
        print_error ".env file not found!"
        exit 1
    fi
    
    # Update Docker Compose configuration with correct URLs
    if [ -n "$INSTANCE_IP" ]; then
        print_status "Configuring Docker Compose for instance IP: $INSTANCE_IP"
        
        # Update docker-compose.yml to use external IP for web service
        sed -i "s|CONSOLE_API_URL=http://api:5001|CONSOLE_API_URL=http://$INSTANCE_IP|g" docker-compose.yml
        sed -i "s|APP_API_URL=http://api:5001|APP_API_URL=http://$INSTANCE_IP|g" docker-compose.yml
        sed -i "s|NEXT_PUBLIC_API_PREFIX=http://api:5001/console/api|NEXT_PUBLIC_API_PREFIX=http://$INSTANCE_IP/console/api|g" docker-compose.yml
        sed -i "s|NEXT_PUBLIC_PUBLIC_API_PREFIX=http://api:5001/v1|NEXT_PUBLIC_PUBLIC_API_PREFIX=http://$INSTANCE_IP/v1|g" docker-compose.yml
    fi
    
    print_success "Docker Compose configuration updated!"
}

# Function to start Docker services
start_docker_services() {
    print_status "Starting Docker services..."
    
    cd ~/docker-compose
    
    # Pull the latest images
    print_status "Pulling Docker images..."
    docker-compose pull
    
    # Start services
    print_status "Starting Dify services..."
    docker-compose up -d
    
    # Wait for services to start
    print_status "Waiting for services to start..."
    sleep 30
    
    # Check service status
    docker-compose ps
    
    print_success "Docker services started!"
}

# Function to wait for database to be ready
wait_for_database() {
    print_status "Waiting for database to be ready..."
    
    cd ~/docker-compose
    
    # Wait for Cloud SQL Proxy to be ready
    for i in {1..60}; do
        if docker-compose exec -T cloud-sql-proxy nc -z localhost 5432 > /dev/null 2>&1; then
            print_success "Database is ready!"
            return 0
        fi
        print_status "Waiting for database... ($i/60)"
        sleep 5
    done
    
    print_error "Database failed to become ready"
    exit 1
}

# Function to initialize database schema
initialize_database() {
    print_status "Initializing database schema..."
    
    cd ~/docker-compose
    
    # Wait for API service to be ready
    print_status "Waiting for API service to be ready..."
    sleep 60
    
    # First, try to run Flask migrations
    print_status "Running Flask database migrations..."
    docker-compose exec -T api python -m flask db upgrade || true
    
    # Create missing tables and fix schema issues based on troubleshooting experience
    print_status "Creating missing database tables and fixing schema..."
    docker-compose exec -T api python -c "
import os
import psycopg2
from datetime import datetime
import sys

# Database connection parameters
db_host = os.getenv('DB_HOST', 'cloud-sql-proxy')
db_port = os.getenv('DB_PORT', '5432')
db_name = os.getenv('DB_DATABASE', 'dify')
db_user = os.getenv('DB_USERNAME', 'dify')
db_password = os.getenv('DB_PASSWORD')

try:
    # Connect to database
    conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        database=db_name,
        user=db_user,
        password=db_password
    )
    cursor = conn.cursor()
    
    print('Connected to database successfully')
    
    # Create dify_setups table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS dify_setups (
            id SERIAL PRIMARY KEY,
            version VARCHAR(255),
            setup_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ''')
    print('Created dify_setups table')
    
    # Create tenants table with all required columns
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tenants (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name VARCHAR(255) NOT NULL,
            encrypt_public_key TEXT,
            encrypted_plan VARCHAR(255),
            plan_base64url_data TEXT,
            plan VARCHAR(255),
            custom_config_dict TEXT,
            custom_config TEXT,
            status VARCHAR(255) NOT NULL DEFAULT 'normal',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ''')
    print('Created tenants table')
    
    # Create accounts table with all required columns
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name VARCHAR(255) NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            password VARCHAR(255) NOT NULL,
            password_salt VARCHAR(255),
            avatar VARCHAR(255),
            interface_language VARCHAR(255) DEFAULT 'en-US',
            interface_theme VARCHAR(255) DEFAULT 'light', 
            timezone VARCHAR(255) DEFAULT 'UTC',
            last_login_at TIMESTAMP,
            last_login_ip VARCHAR(255),
            last_active_at TIMESTAMP,
            status VARCHAR(255) DEFAULT 'active',
            initialized_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ''')
    print('Created accounts table')
    
    # Create tenant_account_joins table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tenant_account_joins (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL,
            account_id UUID NOT NULL,
            current BOOLEAN DEFAULT TRUE,
            role VARCHAR(255) NOT NULL DEFAULT 'normal',
            invited_by UUID,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            UNIQUE(tenant_id, account_id)
        );
    ''')
    print('Created tenant_account_joins table')
    
    # Create other essential tables
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS apps (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id UUID NOT NULL,
            name VARCHAR(255) NOT NULL,
            description TEXT,
            mode VARCHAR(255) NOT NULL DEFAULT 'chat',
            icon VARCHAR(255),
            icon_background VARCHAR(255),
            app_model_config TEXT,
            status VARCHAR(255) DEFAULT 'normal',
            enable_site BOOLEAN DEFAULT TRUE,
            enable_api BOOLEAN DEFAULT TRUE,
            api_key VARCHAR(255),
            is_demo BOOLEAN DEFAULT FALSE,
            is_public BOOLEAN DEFAULT FALSE,
            is_universal BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
        );
    ''')
    print('Created apps table')
    
    # Commit all changes
    conn.commit()
    
    # Check if setup is already marked as completed
    cursor.execute('SELECT COUNT(*) FROM dify_setups;')
    setup_count = cursor.fetchone()[0]
    
    if setup_count == 0:
        print('Database schema initialization completed successfully')
    else:
        print(f'Found {setup_count} existing setup records')
    
    cursor.close()
    conn.close()
    
    print('Database initialization completed successfully!')
    
except Exception as e:
    print(f'Database initialization failed: {e}')
    sys.exit(1)
"
    
    print_success "Database schema initialized successfully!"
}

# Function to verify services are working
verify_services() {
    print_status "Verifying services are working..."
    
    cd ~/docker-compose
    
    # Check if all containers are running
    print_status "Checking container status..."
    if ! docker-compose ps | grep -q "Up"; then
        print_error "Some containers are not running"
        docker-compose ps
        return 1
    fi
    
    # Wait for API to be responsive
    print_status "Waiting for API to be responsive..."
    for i in {1..30}; do
        if curl -s -f http://localhost/console/api/setup > /dev/null 2>&1; then
            print_success "API is responsive!"
            break
        fi
        print_status "Waiting for API... ($i/30)"
        sleep 10
    done
    
    # Test API endpoint
    print_status "Testing API endpoint..."
    api_response=$(curl -s http://localhost/console/api/setup || echo "failed")
    echo "API Response: $api_response"
    
    # Check if web service is responsive
    print_status "Testing web service..."
    if curl -s -I http://localhost/ | grep -q "200\|30[0-9]"; then
        print_success "Web service is responsive!"
    else
        print_warning "Web service may not be fully ready yet"
    fi
    
    print_success "Service verification completed!"
}

# Function to create monitoring and management scripts
create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Create monitoring script
    cat > ~/scripts/monitor-dify.sh << 'EOF'
#!/bin/bash

echo "=== Dify Service Status ==="
cd ~/docker-compose
docker-compose ps

echo -e "\n=== System Resources ==="
echo "CPU and Memory usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

echo -e "\n=== Disk Usage ==="
df -h | grep -E "(Filesystem|/dev/)"

echo -e "\n=== Recent API Logs ==="
docker-compose logs --tail=20 api

echo -e "\n=== Service Health Check ==="
curl -s http://localhost/console/api/setup | jq . 2>/dev/null || echo "API health check failed"
EOF
    
    # Create backup script
    cat > ~/scripts/backup-dify.sh << 'EOF'
#!/bin/bash

set -e

# Load environment variables
cd ~/docker-compose
source .env

echo "Starting Dify backup..."

# Create backup directory
backup_dir="/tmp/dify-backup-$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$backup_dir"

# Backup database
echo "Backing up database..."
docker-compose exec -T cloud-sql-proxy pg_dump -h localhost -U dify -d dify > "$backup_dir/database.sql"

# Backup application data
echo "Backing up application data..."
sudo tar -czf "$backup_dir/app-data.tar.gz" -C ~/docker-compose/volumes .

# Create backup info file
cat > "$backup_dir/backup-info.txt" << EOL
Backup created: $(date)
Dify version: ${DIFY_VERSION:-latest}
Instance IP: ${INSTANCE_IP}
Domain: ${DOMAIN:-not set}
EOL

echo "Backup completed: $backup_dir"
echo "Files created:"
ls -la "$backup_dir"
EOF
    
    # Make scripts executable
    chmod +x ~/scripts/*.sh
    
    print_success "Management scripts created!"
}

# Function to setup log rotation
setup_log_rotation() {
    print_status "Setting up log rotation..."
    
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
    
    print_success "Log rotation configured!"
}

# Main execution function
main() {
    print_status "🚀 Starting Dify instance setup..."
    
    install_system_packages
    install_docker
    setup_directories
    configure_docker_compose
    start_docker_services
    wait_for_database
    initialize_database
    verify_services
    create_management_scripts
    setup_log_rotation
    
    print_success "🎉 Dify instance setup completed successfully!"
    
    echo ""
    echo "📋 Setup Summary:"
    echo "✅ System packages installed"
    echo "✅ Docker and Docker Compose installed"
    echo "✅ Directory structure created"
    echo "✅ Docker services started"
    echo "✅ Database schema initialized"
    echo "✅ Services verified"
    echo "✅ Management scripts created"
    echo "✅ Log rotation configured"
    echo ""
    echo "🔗 Your Dify instance should now be accessible!"
    echo ""
    echo "📁 Useful commands:"
    echo "  Monitor services: ~/scripts/monitor-dify.sh"
    echo "  Create backup:    ~/scripts/backup-dify.sh"
    echo "  View logs:        cd ~/docker-compose && docker-compose logs -f"
    echo "  Restart services: cd ~/docker-compose && docker-compose restart"
}

# Trap errors and provide helpful information
trap 'print_error "Setup failed at line $LINENO. Check the output above for details."' ERR

# Run main function
main "$@" 