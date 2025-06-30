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

# Check if domain and email are provided
if [ $# -ne 2 ]; then
    print_error "Usage: $0 <domain> <email>"
    echo "Example: $0 dify.example.com admin@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=$2

# Function to validate domain accessibility
validate_domain() {
    print_status "Validating domain accessibility..."
    
    # Get external IP
    EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
    
    # Check if domain resolves to this server
    DOMAIN_IP=$(dig +short $DOMAIN | head -n1)
    
    if [ "$DOMAIN_IP" != "$EXTERNAL_IP" ]; then
        print_warning "Domain $DOMAIN resolves to $DOMAIN_IP, but this server's IP is $EXTERNAL_IP"
        print_warning "Please ensure your domain points to $EXTERNAL_IP"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Domain validation successful!"
    fi
}

# Function to obtain SSL certificate
obtain_ssl_certificate() {
    print_status "Obtaining SSL certificate for $DOMAIN..."
    
    cd ~/docker-compose
    
    # Stop nginx temporarily
    docker-compose stop nginx
    
    # Start a temporary nginx container for the challenge
    docker run --rm -d \
        --name temp-nginx \
        -p 80:80 \
        -v "$(pwd)/volumes/certbot/www:/var/www/certbot:ro" \
        nginx:alpine \
        sh -c 'echo "server { listen 80; location /.well-known/acme-challenge/ { root /var/www/certbot; } location / { return 200 \"OK\"; add_header Content-Type text/plain; } }" > /etc/nginx/conf.d/default.conf && nginx -g "daemon off;"'
    
    sleep 5
    
    # Obtain certificate
    docker-compose run --rm certbot \
        certonly --webroot \
        --webroot-path=/var/www/certbot \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        -d $DOMAIN
    
    # Stop temporary nginx
    docker stop temp-nginx || true
    
    print_success "SSL certificate obtained successfully!"
}

# Function to configure nginx for SSL
configure_nginx_ssl() {
    print_status "Configuring Nginx for SSL..."
    
    # Update nginx configuration to enable SSL
    sed -i "s|# ssl_certificate|ssl_certificate|g" ~/docker-compose/nginx/conf.d/dify.conf
    sed -i "s|# ssl_certificate_key|ssl_certificate_key|g" ~/docker-compose/nginx/conf.d/dify.conf
    
    # Enable HTTPS redirect
    sed -i "s|# location / {|location / {|g" ~/docker-compose/nginx/conf.d/dify.conf
    sed -i "s|#     return 301|    return 301|g" ~/docker-compose/nginx/conf.d/dify.conf
    sed -i "s|# }|}|g" ~/docker-compose/nginx/conf.d/dify.conf
    
    # Comment out the temporary HTTP proxy
    sed -i '/# Temporary direct proxy/,/^    }$/ s/^/    # /' ~/docker-compose/nginx/conf.d/dify.conf
    
    print_success "Nginx SSL configuration updated!"
}

# Function to start services with SSL
start_services_with_ssl() {
    print_status "Starting services with SSL enabled..."
    
    cd ~/docker-compose
    
    # Start nginx with SSL configuration
    docker-compose up -d nginx
    
    # Start certbot for automatic renewal
    docker-compose up -d certbot
    
    # Verify SSL is working
    sleep 10
    
    if curl -sSf https://$DOMAIN/health > /dev/null; then
        print_success "SSL is working correctly!"
    else
        print_warning "SSL might not be working properly. Please check the configuration."
    fi
    
    print_success "Services started with SSL enabled!"
}

# Function to setup automatic certificate renewal
setup_auto_renewal() {
    print_status "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > ~/scripts/renew-ssl.sh << 'EOF'
#!/bin/bash

cd ~/docker-compose

# Attempt to renew certificates
docker-compose run --rm certbot renew

# Reload nginx if certificates were renewed
if [ $? -eq 0 ]; then
    docker-compose exec nginx nginx -s reload
    echo "$(date): SSL certificates renewed and nginx reloaded" >> /var/log/dify/ssl-renewal.log
fi
EOF
    
    chmod +x ~/scripts/renew-ssl.sh
    
    # Add to crontab (runs twice daily)
    (crontab -l 2>/dev/null; echo "0 12,0 * * * ~/scripts/renew-ssl.sh") | crontab -
    
    print_success "Automatic SSL renewal setup completed!"
}

# Function to update environment for HTTPS
update_environment() {
    print_status "Updating environment configuration for HTTPS..."
    
    # Update .env file to use HTTPS URLs
    sed -i "s|http://${DOMAIN}|https://${DOMAIN}|g" ~/.env
    
    # Restart API and Web services to pick up new environment
    cd ~/docker-compose
    docker-compose restart api web worker
    
    print_success "Environment updated for HTTPS!"
}

# Function to display final SSL status
show_ssl_status() {
    print_success "🔒 SSL setup completed successfully!"
    echo ""
    echo "SSL Certificate Information:"
    echo "  Domain: $DOMAIN"
    echo "  Certificate Path: ~/docker-compose/volumes/certbot/conf/live/$DOMAIN/"
    echo ""
    echo "Access Information:"
    echo "  HTTPS URL: https://$DOMAIN"
    echo "  HTTP URL: http://$DOMAIN (redirects to HTTPS)"
    echo ""
    echo "Certificate Management:"
    echo "  Manual renewal: ~/scripts/renew-ssl.sh"
    echo "  Automatic renewal: Configured (runs twice daily)"
    echo ""
    echo "SSL Verification:"
    echo "  Test command: curl -I https://$DOMAIN"
    echo "  SSL Labs: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
}

# Function to rollback in case of failure
rollback_ssl() {
    print_error "SSL setup failed. Rolling back changes..."
    
    # Restore original nginx configuration
    git checkout HEAD -- ~/docker-compose/nginx/conf.d/dify.conf 2>/dev/null || {
        print_warning "Could not restore nginx config from git. Manual restoration may be needed."
    }
    
    # Stop and restart nginx
    cd ~/docker-compose
    docker-compose restart nginx
    
    print_warning "Rollback completed. Please check the configuration manually."
}

# Main execution with error handling
main() {
    print_status "Starting SSL setup for domain: $DOMAIN"
    
    # Set trap for cleanup on failure
    trap rollback_ssl ERR
    
    validate_domain
    obtain_ssl_certificate
    configure_nginx_ssl
    start_services_with_ssl
    setup_auto_renewal
    update_environment
    show_ssl_status
    
    # Clear trap
    trap - ERR
    
    print_success "SSL setup completed successfully!"
}

# Validate input
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    print_error "Invalid domain format: $DOMAIN"
    exit 1
fi

if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    print_error "Invalid email format: $EMAIL"
    exit 1
fi

# Run main function
main 