# 🚀 Installation Instructions

## Prerequisites

1. **Google Cloud Account** with billing enabled
2. **Required Tools**: 
   - [gcloud CLI](https://cloud.google.com/sdk/docs/install)
   - [Terraform](https://www.terraform.io/downloads.html)
   - [Docker](https://docs.docker.com/get-docker/) (for local testing)

3. **Authentication**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

## Quick Installation

### 1. Clone and Configure

```bash
# Clone the repository
git clone https://github.com/your-username/dify-gcp.git
cd dify-gcp

# Copy and edit configuration files
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp .env.example .env

# Edit terraform.tfvars with your GCP project details
nano terraform/terraform.tfvars

# Edit .env with your application settings
nano .env
```

### 2. Deploy Infrastructure

```bash
# Deploy with Terraform
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Configure Application

```bash
# SSH to the instance
gcloud compute ssh your-project-dify-instance --zone=your-zone

# Initialize database
sudo /opt/dify/scripts/init-database.sh

# Configure email (optional)
sudo /opt/dify/scripts/setup-email.sh gmail your-email@gmail.com your-app-password
```

### 4. Access Your Instance

- **URL**: https://your-domain.com (or instance IP)
- **Admin**: admin@dify.local
- **Password**: your-admin-password

## Configuration

### Required Variables

Edit `terraform/terraform.tfvars`:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
domain_name = "your-domain.com"  # Optional
```

Edit `.env`:
```bash
SECRET_KEY=your-secret-key-here
DB_PASSWORD=your-db-password
CONSOLE_API_URL=https://your-domain.com
APP_API_URL=https://your-domain.com
```

### Optional Email Configuration

For email functionality, configure SMTP settings in `.env`:
```bash
SMTP_SERVER=smtp.gmail.com
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

## Security Notes

- Never commit `.env` or `terraform.tfvars` files
- Use strong passwords for all credentials
- Enable 2FA on your Google Cloud account
- Regularly update SSL certificates
- Monitor access logs

## Troubleshooting

Run the system status check:
```bash
sudo /opt/dify/scripts/system-status.sh
```

For more help, see the main [README.md](README.md) file.
