#!/bin/bash

# Test script for Dify GCP deployment validation
# This script performs comprehensive health checks on the deployed Dify instance

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "🧪 Dify GCP Deployment Health Check"
    echo "========================================"
    echo -e "${NC}"
}

# Global variables
PROJECT_ID=""
ZONE=""
INSTANCE_NAME=""
DOMAIN=""
EXTERNAL_IP=""

# Function to get deployment info from Terraform
get_deployment_info() {
    print_info "Gathering deployment information..."
    
    if [ ! -d "terraform" ] || [ ! -f "terraform/terraform.tfstate" ]; then
        print_error "Terraform state not found. Please ensure you've deployed first."
        exit 1
    fi
    
    cd terraform
    
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
    ZONE=$(terraform output -raw instance_zone 2>/dev/null || echo "")
    INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null || echo "")
    EXTERNAL_IP=$(terraform output -raw instance_external_ip 2>/dev/null || echo "")
    DOMAIN=$(terraform output -raw access_url 2>/dev/null | sed 's|https\?://||' || echo "")
    
    cd ..
    
    if [ -z "$PROJECT_ID" ] || [ -z "$ZONE" ] || [ -z "$INSTANCE_NAME" ]; then
        print_error "Could not retrieve deployment information from Terraform state."
        exit 1
    fi
    
    print_success "Retrieved deployment information:"
    echo "  Project: $PROJECT_ID"
    echo "  Zone: $ZONE"
    echo "  Instance: $INSTANCE_NAME"
    echo "  External IP: $EXTERNAL_IP"
    if [ -n "$DOMAIN" ]; then
        echo "  Domain: $DOMAIN"
    fi
    echo ""
}

# Function to test GCP infrastructure
test_infrastructure() {
    print_info "Testing GCP infrastructure..."
    
    # Test instance status
    if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" | grep -q "RUNNING"; then
        print_success "Compute instance is running"
    else
        print_error "Compute instance is not running"
        return 1
    fi
    
    # Test Cloud SQL instance
    local sql_instance="${PROJECT_ID}-dify-db"
    if gcloud sql instances describe "$sql_instance" --project="$PROJECT_ID" --format="value(state)" | grep -q "RUNNABLE"; then
        print_success "Cloud SQL instance is running"
    else
        print_error "Cloud SQL instance is not running"
        return 1
    fi
    
    # Test Redis instance
    local redis_instance="${PROJECT_ID}-dify-redis"
    if gcloud redis instances describe "$redis_instance" --region="$(echo $ZONE | sed 's/-[a-z]$//')" --project="$PROJECT_ID" --format="value(state)" | grep -q "READY"; then
        print_success "Redis instance is ready"
    else
        print_error "Redis instance is not ready"
        return 1
    fi
    
    # Test storage bucket
    local bucket_name="${PROJECT_ID}-dify-storage"
    if gsutil ls "gs://$bucket_name" > /dev/null 2>&1; then
        print_success "Storage bucket is accessible"
    else
        print_error "Storage bucket is not accessible"
        return 1
    fi
    
    echo ""
}

# Function to test network connectivity
test_connectivity() {
    print_info "Testing network connectivity..."
    
    # Test SSH connectivity
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="echo 'SSH connection successful'" --quiet > /dev/null 2>&1; then
        print_success "SSH connectivity working"
    else
        print_error "SSH connectivity failed"
        return 1
    fi
    
    # Test HTTP connectivity
    if curl -s --connect-timeout 10 "http://$EXTERNAL_IP/health" | grep -q "healthy"; then
        print_success "HTTP health endpoint responding"
    else
        print_warning "HTTP health endpoint not responding (may still be starting up)"
    fi
    
    # Test HTTPS connectivity (if domain configured)
    if [ -n "$DOMAIN" ] && [[ "$DOMAIN" != *"$EXTERNAL_IP"* ]]; then
        if curl -s --connect-timeout 10 "https://$DOMAIN/health" | grep -q "healthy"; then
            print_success "HTTPS health endpoint responding"
        else
            print_warning "HTTPS health endpoint not responding (SSL may still be configuring)"
        fi
    fi
    
    echo ""
}

# Function to test Docker services
test_docker_services() {
    print_info "Testing Docker services on instance..."
    
    local docker_status=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="cd ~/docker-compose && docker-compose ps --format table" --quiet 2>/dev/null)
    
    if echo "$docker_status" | grep -q "Up"; then
        print_success "Docker services are running"
        
        # Test individual services
        local services=("api" "web" "worker" "nginx" "cloud-sql-proxy")
        for service in "${services[@]}"; do
            if echo "$docker_status" | grep "$service" | grep -q "Up"; then
                print_success "Service $service is running"
            else
                print_warning "Service $service may not be running correctly"
            fi
        done
    else
        print_error "Docker services are not running properly"
        return 1
    fi
    
    echo ""
}

# Function to test application functionality
test_application() {
    print_info "Testing Dify application functionality..."
    
    local base_url="http://$EXTERNAL_IP"
    if [ -n "$DOMAIN" ] && [[ "$DOMAIN" != *"$EXTERNAL_IP"* ]]; then
        base_url="https://$DOMAIN"
    fi
    
    # Test main page
    if curl -s --connect-timeout 10 "$base_url" | grep -q "Dify\|<!DOCTYPE html>"; then
        print_success "Main application page accessible"
    else
        print_warning "Main application page not accessible (may still be initializing)"
    fi
    
    # Test API health
    if curl -s --connect-timeout 10 "$base_url/v1/health" > /dev/null 2>&1; then
        print_success "API health endpoint accessible"
    else
        print_warning "API health endpoint not accessible"
    fi
    
    echo ""
}

# Function to check logs for errors
check_logs() {
    print_info "Checking recent logs for errors..."
    
    local log_output=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="cd ~/docker-compose && docker-compose logs --tail=20 api web worker 2>/dev/null | grep -i error | tail -5" --quiet 2>/dev/null)
    
    if [ -z "$log_output" ]; then
        print_success "No recent errors found in logs"
    else
        print_warning "Some errors found in recent logs:"
        echo "$log_output"
    fi
    
    echo ""
}

# Function to display resource usage
show_resource_usage() {
    print_info "Current resource usage:"
    
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --command="
        echo 'CPU and Memory:'
        top -bn1 | grep 'Cpu(s)' | head -1
        free -h | grep -E 'Mem|Swap'
        echo ''
        echo 'Disk Usage:'
        df -h / | tail -1
        echo ''
        echo 'Docker Container Status:'
        cd ~/docker-compose && docker-compose ps --format table
    " --quiet 2>/dev/null || print_warning "Could not retrieve resource usage"
    
    echo ""
}

# Function to display access information
show_access_info() {
    print_info "🎉 Deployment test completed!"
    echo ""
    echo "Access Information:"
    echo "=================="
    
    if [ -n "$DOMAIN" ] && [[ "$DOMAIN" != *"$EXTERNAL_IP"* ]]; then
        echo "🌐 Primary URL: https://$DOMAIN"
        echo "🔒 HTTP redirect: http://$DOMAIN → https://$DOMAIN"
    fi
    echo "🖥️  Direct IP access: http://$EXTERNAL_IP"
    echo "💻 SSH access: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
    echo ""
    
    echo "Management Commands:"
    echo "==================="
    echo "📊 View logs: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID --command='cd ~/docker-compose && docker-compose logs -f'"
    echo "🔄 Restart services: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID --command='cd ~/docker-compose && docker-compose restart'"
    echo "📈 Monitor resources: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID --command='~/scripts/monitor-dify.sh'"
    echo "🔧 Update Dify: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID --command='~/scripts/update-dify.sh'"
}

# Main execution
main() {
    print_header
    
    get_deployment_info
    
    local all_tests_passed=true
    
    if ! test_infrastructure; then
        all_tests_passed=false
    fi
    
    if ! test_connectivity; then
        all_tests_passed=false
    fi
    
    if ! test_docker_services; then
        all_tests_passed=false
    fi
    
    test_application  # Non-critical, just warnings
    check_logs        # Non-critical, just informational
    show_resource_usage
    
    if [ "$all_tests_passed" = true ]; then
        print_success "All critical tests passed! ✅"
    else
        print_warning "Some tests failed. Check the output above for details."
    fi
    
    show_access_info
}

# Run main function
main 