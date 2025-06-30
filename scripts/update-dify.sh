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

# Configuration
BACKUP_DIR="/opt/dify/backups"
LOG_FILE="/var/log/dify/update.log"
COMPOSE_DIR="$HOME/docker-compose"

# Default values
DIFY_VERSION="latest"
SKIP_BACKUP=false
FORCE_UPDATE=false

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION    Specify Dify version to update to (default: latest)"
    echo "  --skip-backup       Skip creating backup before update"
    echo "  --force             Force update even if same version"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Update to latest version"
    echo "  $0 --version 0.6.0          # Update to specific version"
    echo "  $0 --skip-backup            # Update without backup"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            DIFY_VERSION="$2"
            shift 2
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to create backup before update
create_backup() {
    if [ "$SKIP_BACKUP" = true ]; then
        print_warning "Skipping backup as requested"
        return
    fi
    
    print_status "Creating backup before update..."
    
    if [ -f "$HOME/scripts/backup-dify.sh" ]; then
        bash "$HOME/scripts/backup-dify.sh"
        print_success "Backup created successfully!"
    else
        print_warning "Backup script not found. Creating manual backup..."
        
        # Create backup directory
        sudo mkdir -p "$BACKUP_DIR"
        
        DATE=$(date +"%Y%m%d_%H%M%S")
        MANUAL_BACKUP_FILE="$BACKUP_DIR/manual_backup_${DATE}.tar.gz"
        
        # Create manual backup
        cd "$COMPOSE_DIR"
        sudo tar -czf "$MANUAL_BACKUP_FILE" volumes/ .env docker-compose.yml
        
        print_success "Manual backup created: $MANUAL_BACKUP_FILE"
    fi
}

# Function to update Dify
update_dify() {
    print_status "Updating Dify to version $DIFY_VERSION..."
    
    cd "$COMPOSE_DIR"
    
    # Update version in environment file
    sed -i "s/DIFY_VERSION=.*/DIFY_VERSION=$DIFY_VERSION/" .env
    
    # Pull new images
    docker-compose pull
    
    # Stop and recreate services
    docker-compose down
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 60
    
    # Run database migrations
    docker-compose exec -T api python -m flask db upgrade
    
    print_success "Dify updated to version $DIFY_VERSION!"
}

# Function to verify update
verify_update() {
    print_status "Verifying update..."
    
    cd "$COMPOSE_DIR"
    
    # Check if all services are running
    if docker-compose ps | grep -q "Up"; then
        print_success "All services are running!"
    else
        print_error "Some services are not running!"
        docker-compose ps
        exit 1
    fi
    
    # Check API health
    if curl -sSf http://localhost/health > /dev/null; then
        print_success "Health check passed!"
    else
        print_error "Health check failed!"
        exit 1
    fi
}

# Main execution
main() {
    print_status "Starting Dify update to version $DIFY_VERSION..."
    
    create_backup
    update_dify
    verify_update
    
    print_success "🎉 Dify update completed successfully!"
}

# Ensure we're in the right directory
if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    print_error "Docker Compose file not found in $COMPOSE_DIR"
    exit 1
fi

# Create log directory if it doesn't exist
sudo mkdir -p "$(dirname "$LOG_FILE")"

# Run main function
main 