#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
DOMAIN=""
ADMIN_EMAIL=""
DIFY_VERSION="latest"

# Function to print colored output
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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it from https://www.terraform.io/downloads.html"
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it from https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if SSH key exists, create if not
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_warning "SSH key not found. Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "dify-gcp-deployment"
        print_success "SSH key generated at ~/.ssh/id_rsa.pub"
    fi
    
    # Check GCP authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        print_error "Not authenticated with GCP. Please run: gcloud auth login"
        exit 1
    fi
    
    print_success "All prerequisites are met!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --project-id PROJECT_ID     GCP Project ID (required)"
    echo "  --region REGION             GCP Region (default: us-central1)"
    echo "  --zone ZONE                 GCP Zone (default: us-central1-a)"
    echo "  --domain DOMAIN             Custom domain for Dify (optional)"
    echo "  --admin-email EMAIL         Admin email for Let's Encrypt (required if domain is set)"
    echo "  --dify-version VERSION      Dify version to deploy (default: latest)"
    echo "  --help                      Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --project-id my-project-123 --domain dify.example.com --admin-email admin@example.com"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --dify-version)
            DIFY_VERSION="$2"
            shift 2
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

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    print_error "Project ID is required. Use --project-id option."
    show_usage
    exit 1
fi

if [[ -n "$DOMAIN" && -z "$ADMIN_EMAIL" ]]; then
    print_error "Admin email is required when domain is specified. Use --admin-email option."
    show_usage
    exit 1
fi

# Function to setup GCP authentication and project
setup_gcp() {
    print_status "Setting up GCP project..."
    
    # Set the project
    gcloud config set project "$PROJECT_ID"
    
    print_status "GCP APIs will be enabled automatically by Terraform..."
    
    print_success "GCP project setup completed!"
}

# Function to deploy infrastructure with Terraform
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    # Initialize Terraform
    terraform init
    
    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
project_id = "$PROJECT_ID"
region = "$REGION"
zone = "$ZONE"
domain = "$DOMAIN"
admin_email = "$ADMIN_EMAIL"
dify_version = "$DIFY_VERSION"
EOF
    
    # Plan and apply
    terraform plan
    terraform apply -auto-approve
    
    # Get outputs
    INSTANCE_IP=$(terraform output -raw instance_external_ip)
    DB_CONNECTION_NAME=$(terraform output -raw db_connection_name)
    DB_PASSWORD=$(terraform output -raw db_password)
    REDIS_HOST=$(terraform output -raw redis_host)
    BUCKET_NAME=$(terraform output -raw storage_bucket_name)
    
    cd ..
    
    print_success "Infrastructure deployed successfully!"
    print_status "Instance IP: $INSTANCE_IP"
}

# Function to deploy Dify application
deploy_application() {
    print_status "Deploying Dify application..."
    
    # Create .env file for Docker Compose
    cat > .env << EOF
# Database Configuration
DB_USERNAME=dify
DB_PASSWORD=$DB_PASSWORD
DB_DATABASE=dify
DB_HOST=localhost
DB_CONNECTION_NAME=$DB_CONNECTION_NAME

# Redis Configuration
REDIS_HOST=$REDIS_HOST
REDIS_PORT=6379
REDIS_DB=0

# Storage Configuration
STORAGE_TYPE=google-storage
GOOGLE_STORAGE_BUCKET_NAME=$BUCKET_NAME

# Application Configuration
SECRET_KEY=$(openssl rand -base64 32)
DIFY_VERSION=$DIFY_VERSION
DOMAIN=${DOMAIN:-$INSTANCE_IP}

# Email Configuration (optional)
${ADMIN_EMAIL:+ADMIN_EMAIL=$ADMIN_EMAIL}
EOF
    
    # Copy deployment files to the instance
    print_status "Copying files to GCP instance..."
    gcloud compute scp --zone="$ZONE" --recurse docker-compose/ scripts/ .env "$PROJECT_ID-dify-instance":~/
    
    # Execute deployment on the instance
    print_status "Executing deployment on the instance..."
    gcloud compute ssh --zone="$ZONE" "$PROJECT_ID-dify-instance" --command="cd ~/ && chmod +x scripts/setup-instance.sh && ./scripts/setup-instance.sh"
    
    print_success "Dify application deployed successfully!"
}

# Function to setup domain and SSL (if provided)
setup_domain() {
    if [[ -n "$DOMAIN" ]]; then
        print_status "Setting up domain and SSL certificate..."
        
        # Instructions for user
        print_warning "Please configure your DNS to point $DOMAIN to $INSTANCE_IP"
        print_status "Waiting for DNS propagation... (you can skip this with Ctrl+C if DNS is already configured)"
        
        # Wait for user confirmation
        read -p "Press Enter when DNS is configured, or Ctrl+C to skip domain setup..."
        
        # Setup SSL certificate
        gcloud compute ssh --zone="$ZONE" "$PROJECT_ID-dify-instance" --command="cd ~/ && ./scripts/setup-ssl.sh $DOMAIN $ADMIN_EMAIL"
        
        print_success "Domain and SSL setup completed!"
    fi
}

# Function to display final information
show_final_info() {
    print_success "🎉 Dify deployment completed successfully!"
    echo ""
    echo "Access Information:"
    if [[ -n "$DOMAIN" ]]; then
        echo "  URL: https://$DOMAIN"
    else
        echo "  URL: http://$INSTANCE_IP"
    fi
    echo "  Admin Panel: /admin"
    echo ""
    echo "Instance Information:"
    echo "  Instance Name: $PROJECT_ID-dify-instance"
    echo "  Zone: $ZONE"
    echo "  External IP: $INSTANCE_IP"
    echo ""
    echo "Next Steps:"
    echo "  1. Visit the URL above to access Dify"
    echo "  2. Create your admin account"
    echo "  3. Configure your AI models and applications"
    echo ""
    echo "Management Commands:"
    echo "  - View logs: gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='docker-compose logs -f'"
    echo "  - Restart services: gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='docker-compose restart'"
    echo "  - Update Dify: gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='./scripts/update-dify.sh'"
}

# Main execution
main() {
    print_status "Starting Dify deployment on GCP..."
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    if [[ -n "$DOMAIN" ]]; then
        echo "Domain: $DOMAIN"
    fi
    echo ""
    
    check_prerequisites
    setup_gcp
    deploy_infrastructure
    deploy_application
    setup_domain
    show_final_info
}

# Run main function
main 