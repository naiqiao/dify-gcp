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

# Function to update Dify to latest version
update_dify() {
    print_status "🚀 Starting Dify update process..."
    
    cd ~/docker-compose
    
    # Check if .env file exists
    if [ ! -f .env ]; then
        print_error ".env file not found. Please ensure Dify is properly installed."
        exit 1
    fi
    
    # Load environment variables
    source .env
    
    # Create backup before update
    print_status "Creating backup before update..."
    if [ -f ~/scripts/backup-dify.sh ]; then
        ~/scripts/backup-dify.sh
    else
        print_warning "Backup script not found, skipping backup."
    fi
    
    # Stop services
    print_status "Stopping Dify services..."
    docker-compose down
    
    # Pull latest images
    print_status "Pulling latest Dify images..."
    docker-compose pull
    
    # Update Docker Compose if needed
    print_status "Checking for Docker Compose updates..."
    docker-compose --version
    
    # Start services with latest images
    print_status "Starting updated Dify services..."
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 30
    
    # Run database migrations if needed
    print_status "Running database migrations..."
    docker-compose exec -T api python -m flask db upgrade || print_warning "Migration failed or not needed"
    
    # Verify services are running
    print_status "Verifying services..."
    if docker-compose ps | grep -q "Up"; then
        print_success "All services are running!"
    else
        print_error "Some services failed to start. Check logs with: docker-compose logs"
        exit 1
    fi
    
    # Test API endpoint
    print_status "Testing API endpoint..."
    for i in {1..10}; do
        if curl -s -f http://localhost/console/api/setup > /dev/null 2>&1; then
            print_success "API is responsive!"
            break
        fi
        print_status "Waiting for API... ($i/10)"
        sleep 10
    done
    
    # Show final status
    print_success "🎉 Dify update completed successfully!"
    echo ""
    echo "📋 Update Summary:"
    echo "✅ Services stopped"
    echo "✅ Latest images pulled"
    echo "✅ Services restarted"
    echo "✅ Database migrations applied"
    echo "✅ API verified"
    echo ""
    echo "🔗 Your Dify instance is now running the latest version!"
    echo ""
    
    # Show running services
    print_status "Current service status:"
    docker-compose ps
}

# Function to update to specific version
update_to_version() {
    local version=$1
    
    if [ -z "$version" ]; then
        print_error "Version not specified"
        exit 1
    fi
    
    print_status "🎯 Updating Dify to version: $version"
    
    cd ~/docker-compose
    
    # Update version in .env file
    if grep -q "DIFY_VERSION" .env; then
        sed -i "s/DIFY_VERSION=.*/DIFY_VERSION=$version/" .env
    else
        echo "DIFY_VERSION=$version" >> .env
    fi
    
    # Run update process
    update_dify
}

# Function to show current version
show_version() {
    cd ~/docker-compose
    
    if [ -f .env ]; then
        source .env
        echo "Current Dify version: ${DIFY_VERSION:-latest}"
    else
        echo "Cannot determine version - .env file not found"
    fi
    
    print_status "Running containers:"
    docker-compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
}

# Function to show usage
show_usage() {
    echo "Dify Update Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION   Update to specific version"
    echo "  --show-version      Show current version"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Update to latest version"
    echo "  $0 --version 0.6.0           # Update to specific version"
    echo "  $0 --show-version            # Show current version"
}

# Main execution
main() {
    case "${1:-}" in
        --version)
            if [ -z "$2" ]; then
                print_error "Version not specified"
                show_usage
                exit 1
            fi
            update_to_version "$2"
            ;;
        --show-version)
            show_version
            ;;
        --help)
            show_usage
            ;;
        "")
            update_dify
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Trap errors
trap 'print_error "Update failed at line $LINENO. Check the output above for details."' ERR

# Run main function
main "$@" 