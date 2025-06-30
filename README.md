# Dify One-Click Deployment on Google Cloud Platform

This repository provides a **complete one-click deployment solution** for [Dify](https://github.com/langgenius/dify), an open-source LLM app development platform, on Google Cloud Platform (GCP).

> **🎯 Zero Manual Configuration Required**: The script automatically creates and configures ALL GCP resources, installs dependencies, sets up databases, configures networking, provisions SSL certificates, and deploys the complete Dify application stack.

## Features

- **🚀 Complete One-Click Deployment**: Fully automated infrastructure and application deployment
- **🏗️ Auto-Infrastructure Creation**: Automatically creates ALL required GCP resources
- **🔒 SSL/TLS Support**: Automatic SSL certificate management with Let's Encrypt
- **💾 Backup & Recovery**: Automated backup system with Google Cloud Storage integration
- **🧪 Comprehensive Testing**: Built-in deployment validation and health checks

## What Gets Created Automatically

- **Infrastructure**: VPC, firewall rules, static IP, service account
- **Compute**: Ubuntu VM with Docker and all dependencies
- **Databases**: Cloud SQL PostgreSQL + Redis instance
- **Storage**: Cloud Storage bucket for file uploads
- **Load Balancer**: HTTP(S) load balancer with SSL (when domain provided)
- **APIs**: All required GCP APIs enabled automatically

**💰 Estimated Cost: ~$190-230/month**

## Prerequisites

1. **GCP Account** with billing enabled
2. **Required Tools**: [gcloud CLI](https://cloud.google.com/sdk/docs/install), [Terraform](https://www.terraform.io/downloads.html), [Docker](https://docs.docker.com/get-docker/)
3. **Authentication**: 
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

## Quick Start

### 1. Check Environment
```bash
./check-env.sh
```

### 2. Deploy (Choose One)

**Option A: Interactive (Recommended)**
```bash
./quick-start.sh
```

**Option B: Direct Deployment**
```bash
# Basic deployment (IP access)
./deploy.sh --project-id your-gcp-project-id

# With custom domain
./deploy.sh --project-id your-gcp-project-id --domain dify.example.com --admin-email admin@example.com
```

**⏱️ Deployment Time: 10-15 minutes**

### 3. Test Deployment
```bash
./test-deployment.sh
```

## Configuration Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--project-id` | GCP Project ID | - | Yes |
| `--region` | GCP Region | us-central1 | No |
| `--zone` | GCP Zone | us-central1-a | No |
| `--domain` | Custom domain for HTTPS | - | No |
| `--admin-email` | Admin email for SSL cert | - | Required if domain set |
| `--dify-version` | Dify version to deploy | latest | No |

## Post-Deployment

### Access Your Instance
- **With Domain**: https://your-domain.com
- **Without Domain**: http://your-instance-ip

### Management Commands
```bash
# SSH into instance
gcloud compute ssh --zone=your-zone your-project-id-dify-instance

# View logs
docker-compose logs -f

# Update Dify
~/scripts/update-dify.sh

# Monitor system
~/scripts/monitor-dify.sh

# Create backup
~/scripts/backup-dify.sh
```

## Troubleshooting

### Common Issues

**Deployment fails**: Check GCP quotas, billing enabled, and required APIs
```bash
./check-env.sh  # Run environment check
```

**Services won't start**: 
```bash
# Check logs
docker-compose logs api web worker

# Check resources
df -h && free -h
```

**SSL issues**:
```bash
# Check certificate status
docker-compose logs certbot

# Manual renewal
~/scripts/renew-ssl.sh
```

### Getting Help
1. Check logs: `docker-compose logs -f`
2. Run health check: `./test-deployment.sh`
3. [Dify Documentation](https://docs.dify.ai/)
4. [GitHub Issues](https://github.com/langgenius/dify/issues)

## Cost Optimization

Default setup uses:
- **Compute**: e2-standard-4 (4 vCPUs, 16GB RAM) ~$120/month
- **Cloud SQL**: db-g1-small ~$25/month  
- **Redis**: 1GB ~$35/month
- **Storage**: ~$10-50/month

To reduce costs, modify `machine_type` in `terraform/variables.tf` or use smaller database tiers.

## Security Features

- VPC network isolation
- Firewall rules (HTTP/HTTPS/SSH only)
- Service account with minimal permissions
- Automatic SSL/TLS encryption
- Regular security updates

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**🎊 Ready to deploy?** Run `./quick-start.sh` to get started!
