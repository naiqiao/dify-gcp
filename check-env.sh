#!/bin/bash

# Environment Check Script for Dify GCP Deployment

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
    echo "=================================="
    echo "🔍 Environment Check for Dify GCP"
    echo "=================================="
    echo -e "${NC}"
}

# Check function template
check_tool() {
    local tool=$1
    local install_url=$2
    
    if command -v $tool &> /dev/null; then
        local version=$($tool --version 2>/dev/null | head -n1 || echo "version unknown")
        print_success "$tool is installed ($version)"
        return 0
    else
        print_error "$tool is not installed"
        print_info "Install from: $install_url"
        return 1
    fi
}

# Check individual requirements
check_requirements() {
    local all_good=true
    
    print_info "Checking required tools..."
    echo ""
    
    # Check gcloud
    if ! check_tool "gcloud" "https://cloud.google.com/sdk/docs/install"; then
        all_good=false
    fi
    
    # Check terraform
    if ! check_tool "terraform" "https://www.terraform.io/downloads.html"; then
        all_good=false
    fi
    
    # Check docker
    if ! check_tool "docker" "https://docs.docker.com/get-docker/"; then
        all_good=false
    fi
    
    # Check curl
    if ! check_tool "curl" "https://curl.se/download.html"; then
        all_good=false
    fi
    
    echo ""
    
    # Check SSH key
    print_info "Checking SSH configuration..."
    if [ -f ~/.ssh/id_rsa.pub ]; then
        print_success "SSH public key found at ~/.ssh/id_rsa.pub"
    else
        print_warning "SSH key not found - will be generated during deployment"
    fi
    
    echo ""
    
    # Check GCP authentication
    print_info "Checking GCP authentication..."
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
        print_success "Authenticated as: $active_account"
        
        # Check application default credentials
        if gcloud auth application-default print-access-token > /dev/null 2>&1; then
            print_success "Application Default Credentials configured"
        else
            print_warning "Application Default Credentials not configured"
            print_info "Run: gcloud auth application-default login"
        fi
    else
        print_error "Not authenticated with GCP"
        print_info "Run: gcloud auth login"
        all_good=false
    fi
    
    echo ""
    
    # Check current project
    print_info "Checking GCP project configuration..."
    local current_project=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$current_project" ]; then
        print_success "Current project: $current_project"
        
        # Check if billing is enabled
        if gcloud beta billing projects describe $current_project > /dev/null 2>&1; then
            print_success "Billing is enabled for project"
        else
            print_warning "Cannot verify billing status - ensure billing is enabled"
        fi
    else
        print_warning "No default project set"
        print_info "Set with: gcloud config set project YOUR_PROJECT_ID"
    fi
    
    echo ""
    
    if [ "$all_good" = true ]; then
        return 0
    else
        return 1
    fi
}

# Check GCP quotas and limits
check_quotas() {
    print_info "Checking GCP quotas (this may take a moment)..."
    
    local current_project=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$current_project" ]; then
        print_warning "No project set - skipping quota check"
        return
    fi
    
    # Check Compute Engine quotas
    local cpu_quota=$(gcloud compute project-info describe --project=$current_project --format="value(quotas[].limit)" --filter="quotas.metric=CPUS" 2>/dev/null | head -n1)
    if [ -n "$cpu_quota" ] && [ "$cpu_quota" -ge 4 ]; then
        print_success "CPU quota: $cpu_quota (sufficient)"
    else
        print_warning "CPU quota may be insufficient (need at least 4 vCPUs)"
    fi
    
    echo ""
}

# Main check function
main() {
    print_header
    
    if check_requirements; then
        print_success "All basic requirements are met!"
    else
        print_error "Some requirements are missing. Please install them before proceeding."
        echo ""
        print_info "After installing missing tools, run this script again to verify."
        exit 1
    fi
    
    echo ""
    check_quotas
    
    echo ""
    print_success "Environment check completed!"
    echo ""
    print_info "You're ready to deploy Dify! Run one of the following:"
    echo "  ./quick-start.sh    # Interactive deployment"
    echo "  ./deploy.sh --help  # See all deployment options"
}

# Run main function
main 