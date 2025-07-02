#!/bin/bash

# Quick Start Script for Dify GCP Deployment
# This script helps new users get started quickly

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "======================================================"
    echo "🚀 Dify One-Click Deployment on Google Cloud Platform"
    echo "======================================================"
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to collect user input
collect_user_input() {
    print_step "Collecting deployment information..."
    
    # Project ID
    while [ -z "$PROJECT_ID" ]; do
        echo -n "Enter your GCP Project ID: "
        read PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            print_error "Project ID cannot be empty!"
        fi
    done
    
    # Region selection
    print_info "Select a region for deployment:"
    echo "1) us-central1 (Iowa, USA)"
    echo "2) us-east1 (South Carolina, USA)"
    echo "3) us-west1 (Oregon, USA)"
    echo "4) europe-west1 (Belgium)"
    echo "5) asia-southeast1 (Singapore)"
    echo "6) Custom region"
    
    while true; do
        echo -n "Choose region (1-6) [default: 1]: "
        read region_choice
        region_choice=${region_choice:-1}
        
        case $region_choice in
            1) REGION="us-central1"; ZONE="us-central1-a"; break;;
            2) REGION="us-east1"; ZONE="us-east1-b"; break;;
            3) REGION="us-west1"; ZONE="us-west1-a"; break;;
            4) REGION="europe-west1"; ZONE="europe-west1-b"; break;;
            5) REGION="asia-southeast1"; ZONE="asia-southeast1-a"; break;;
            6) 
                echo -n "Enter custom region: "
                read REGION
                echo -n "Enter zone in $REGION: "
                read ZONE
                break;;
            *) print_error "Invalid choice. Please select 1-6.";;
        esac
    done
    
    # Domain configuration
    echo -n "Do you have a custom domain? (y/N): "
    read has_domain
    
    if [[ "$has_domain" =~ ^[Yy]$ ]]; then
        while [ -z "$DOMAIN" ]; do
            echo -n "Enter your domain (e.g., dify.yourdomain.com): "
            read DOMAIN
            if [ -z "$DOMAIN" ]; then
                print_error "Domain cannot be empty!"
            fi
        done
        
        while [ -z "$ADMIN_EMAIL" ]; do
            echo -n "Enter admin email for SSL certificate: "
            read ADMIN_EMAIL
            if [ -z "$ADMIN_EMAIL" ]; then
                print_error "Admin email cannot be empty!"
            fi
        done
    fi
    
    # Dify version
    echo -n "Dify version to deploy [default: latest]: "
    read DIFY_VERSION
    DIFY_VERSION=${DIFY_VERSION:-latest}
}

# Function to display deployment summary
show_deployment_summary() {
    print_step "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    if [ -n "$DOMAIN" ]; then
        echo "Domain: $DOMAIN"
        echo "Admin Email: $ADMIN_EMAIL"
    else
        echo "Domain: Will use instance IP"
    fi
    echo "Dify Version: $DIFY_VERSION"
    echo "=================="
    echo ""
    
    print_warning "This deployment will create GCP resources that incur costs."
    print_info "Estimated monthly cost: ~\$190-230 USD"
    echo ""
    
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled."
        exit 0
    fi
}

# Function to run the deployment
run_deployment() {
    print_step "Starting deployment..."
    
    # Build command
    DEPLOY_CMD="./deploy.sh --project-id $PROJECT_ID --region $REGION --zone $ZONE --dify-version $DIFY_VERSION"
    
    if [ -n "$DOMAIN" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --domain $DOMAIN --admin-email $ADMIN_EMAIL"
    fi
    
    print_info "Running: $DEPLOY_CMD"
    echo ""
    
    # Execute deployment
    exec $DEPLOY_CMD
}

# Main execution
main() {
    print_header
    
    print_info "This script will help you deploy Dify on Google Cloud Platform."
    print_info "Make sure you have gcloud CLI, Terraform, and Docker installed."
    echo ""
    
    collect_user_input
    show_deployment_summary
    run_deployment
}

# Run main function
main 