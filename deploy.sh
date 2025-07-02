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

# Function to show usage
show_usage() {
    echo "Dify One-Click Deployment on Google Cloud Platform"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --project-id PROJECT_ID     GCP Project ID"
    echo ""
    echo "Optional Options:"
    echo "  --region REGION             GCP Region (default: us-central1)"
    echo "  --zone ZONE                 GCP Zone (default: us-central1-a)"
    echo "  --domain DOMAIN             Custom domain for HTTPS access"
    echo "  --admin-email EMAIL         Admin email for SSL certificate (required with domain)"
    echo "  --dify-version VERSION      Dify version to deploy (default: latest)"
    echo "  --help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic deployment with IP access:"
    echo "  $0 --project-id my-project-123"
    echo ""
    echo "  # Deployment with custom domain and SSL:"
    echo "  $0 --project-id my-project-123 --domain dify.example.com --admin-email admin@example.com"
    echo ""
    echo "Estimated deployment time: 10-15 minutes"
    echo "Estimated monthly cost: $190-230 USD"
}

# Function to check all prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local errors=0
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        errors=$((errors + 1))
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it from https://www.terraform.io/downloads.html"
        errors=$((errors + 1))
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it from https://docs.docker.com/get-docker/"
        errors=$((errors + 1))
    fi
    
    # Check GCP authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        print_error "Not authenticated with GCP. Please run: gcloud auth login"
        errors=$((errors + 1))
    fi
    
    # Check application default credentials
    if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
        print_warning "Application default credentials not set. Running: gcloud auth application-default login"
        gcloud auth application-default login
    fi
    
    # Check if SSH key exists, create if not
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_warning "SSH key not found. Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "dify-gcp-deployment"
        print_success "SSH key generated at ~/.ssh/id_rsa.pub"
    fi
    
    # Check GCP project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        print_error "Cannot access project '$PROJECT_ID'. Please check project ID and permissions."
        errors=$((errors + 1))
    fi
    
    # Check billing is enabled
    local billing_account=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        print_error "Billing is not enabled for project '$PROJECT_ID'. Please enable billing in the GCP Console."
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        print_error "Found $errors prerequisite issue(s). Please fix them before proceeding."
        exit 1
    fi
    
    print_success "All prerequisites are met!"
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

# Function to setup GCP project
setup_gcp_project() {
    print_status "Setting up GCP project..."
    
    # Set the project
    gcloud config set project "$PROJECT_ID"
    
    # Set compute region and zone
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    print_success "GCP project configured successfully!"
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
    print_status "Creating infrastructure... This may take 5-10 minutes."
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
    print_status "Database connection: $DB_CONNECTION_NAME"
}

# Function to prepare application deployment
prepare_application_deployment() {
    print_status "Preparing application deployment..."
    
    # Generate a secure secret key
    SECRET_KEY=$(openssl rand -base64 32)
    
    # Create environment file
    cat > docker-compose/.env << EOF
# Database Configuration
DB_USERNAME=dify
DB_PASSWORD=$DB_PASSWORD
DB_DATABASE=dify
DB_HOST=cloud-sql-proxy
DB_PORT=5432
DB_CONNECTION_NAME=$DB_CONNECTION_NAME

# Redis Configuration
REDIS_HOST=$REDIS_HOST
REDIS_PORT=6379
REDIS_DB=0

# Storage Configuration
STORAGE_TYPE=google-storage
GOOGLE_STORAGE_BUCKET_NAME=$BUCKET_NAME

# Application Configuration
SECRET_KEY=$SECRET_KEY
DIFY_VERSION=$DIFY_VERSION
INSTANCE_IP=$INSTANCE_IP

# Domain Configuration
${DOMAIN:+DOMAIN=$DOMAIN}
${ADMIN_EMAIL:+ADMIN_EMAIL=$ADMIN_EMAIL}
EOF
    
    print_success "Application configuration prepared!"
}

# Function to deploy application to instance
deploy_application() {
    print_status "Deploying Dify application to instance..."
    
    local instance_name="$PROJECT_ID-dify-instance"
    
    # Wait for instance to be ready
    print_status "Waiting for instance to be ready..."
    for i in {1..30}; do
        if gcloud compute ssh --zone="$ZONE" "$instance_name" --command="echo 'ready'" > /dev/null 2>&1; then
            break
        fi
        sleep 10
    done
    
    # Copy files to instance
    print_status "Copying deployment files to instance..."
    gcloud compute scp --zone="$ZONE" --recurse docker-compose/ scripts/ "$instance_name":~/
    
    # Execute deployment on instance
    print_status "Executing deployment on instance... This may take 5-10 minutes."
    gcloud compute ssh --zone="$ZONE" "$instance_name" --command="
        cd ~/
        chmod +x scripts/*.sh
        ./scripts/setup-instance.sh
    "
    
    print_success "Dify application deployed successfully!"
}

# Function to setup domain and SSL (if provided)
setup_domain_and_ssl() {
    if [[ -n "$DOMAIN" ]]; then
        print_status "Setting up domain and SSL certificate..."
        
        local lb_ip
        cd terraform
        lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
        cd ..
        
        if [[ -n "$lb_ip" ]]; then
            print_warning "IMPORTANT: Configure your DNS to point $DOMAIN to $lb_ip"
            print_status "DNS Configuration Required:"
            print_status "  - Create an A record: $DOMAIN -> $lb_ip"
            print_status "  - SSL certificate will be automatically provisioned once DNS is configured"
            print_status "  - This may take 10-60 minutes after DNS propagation"
        fi
        
        print_success "Domain setup initiated!"
    fi
}

# Function to run post-deployment verification
verify_deployment() {
    print_status "Verifying deployment..."
    
    local instance_name="$PROJECT_ID-dify-instance"
    
    # Check if services are running
    print_status "Checking service status..."
    gcloud compute ssh --zone="$ZONE" "$instance_name" --command="
        cd ~/docker-compose
        docker-compose ps
        echo ''
        echo '=== Service Health Check ==='
        curl -s -o /dev/null -w 'HTTP Status: %{http_code}' http://localhost/console/api/setup || echo 'API not ready yet'
        echo ''
    "
    
    print_success "Deployment verification completed!"
}

# Function to display final information
show_deployment_info() {
    print_success "🎉 Dify deployment completed successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 DEPLOYMENT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🌐 Access Information:"
    if [[ -n "$DOMAIN" ]]; then
        echo "   Primary URL:    https://$DOMAIN (after DNS configuration)"
        echo "   Fallback URL:   http://$INSTANCE_IP"
    else
        echo "   URL:            http://$INSTANCE_IP"
    fi
    echo ""
    echo "🖥️  Instance Information:"
    echo "   Name:           $PROJECT_ID-dify-instance"
    echo "   Zone:           $ZONE"
    echo "   External IP:    $INSTANCE_IP"
    echo ""
    echo "🔑 Next Steps:"
    echo "   1. Visit the URL above to access Dify"
    echo "   2. Complete the initial setup by creating your admin account"
    echo "   3. Configure your AI models and start building applications"
    
    if [[ -n "$DOMAIN" ]]; then
        echo ""
        echo "🌍 DNS Configuration (Required for HTTPS):"
        local lb_ip
        cd terraform
        lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
        cd ..
        if [[ -n "$lb_ip" ]]; then
            echo "   Create DNS A record: $DOMAIN -> $lb_ip"
        fi
    fi
    
    echo ""
    echo "🛠️  Management Commands:"
    echo "   SSH to instance:    gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance"
    echo "   View logs:          gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='cd ~/docker-compose && docker-compose logs -f'"
    echo "   Restart services:   gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='cd ~/docker-compose && docker-compose restart'"
    echo "   Update Dify:        gcloud compute ssh --zone=$ZONE $PROJECT_ID-dify-instance --command='~/scripts/update-dify.sh'"
    echo ""
    echo "💰 Estimated Monthly Cost: ~$190-230 USD"
    echo "📚 Documentation: https://docs.dify.ai/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution function
main() {
    echo ""
    echo "🚀 Starting Dify One-Click Deployment on Google Cloud Platform"
    echo ""
    echo "Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region:     $REGION"
    echo "  Zone:       $ZONE"
    if [[ -n "$DOMAIN" ]]; then
        echo "  Domain:     $DOMAIN"
    fi
    echo "  Version:    $DIFY_VERSION"
    echo ""
    
    check_prerequisites
    setup_gcp_project
    deploy_infrastructure
    prepare_application_deployment
    deploy_application
    setup_domain_and_ssl
    verify_deployment
    show_deployment_info
    
    print_success "Deployment completed! 🎉"
}

# Trap errors and provide helpful information
trap 'print_error "Deployment failed at line $LINENO. Check the output above for details."' ERR

# Run main function
main "$@" 