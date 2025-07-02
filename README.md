# 🚀 Dify GCP Complete Deployment

Complete production deployment of [Dify](https://dify.ai) on Google Cloud Platform with comprehensive database schema, email configuration, and monitoring.

## 📋 Project Overview

This repository provides a **complete, production-ready** Dify deployment on GCP including:

- ✅ **Complete Database Schema** (62 tables)
- ✅ **Load Balancer with SSL** 
- ✅ **Cloud SQL PostgreSQL Database**
- ✅ **Email Configuration & Testing**
- ✅ **Redis for Session Management**
- ✅ **Comprehensive Monitoring**
- ✅ **Automated Scripts & Tools**

## 🏗️ Architecture

```
Internet → Load Balancer → VM Instance → Docker Containers
                            ↓
                     Cloud SQL + Redis
```

### Components

| Component | Resource | Purpose |
|-----------|----------|---------|
| **Load Balancer** | `your-project-dify-*` | SSL termination, traffic distribution |
| **VM Instance** | `your-project-dify-instance` | Application hosting |
| **Database** | `your-project-dify-db` | PostgreSQL 15 with 62 tables |
| **Domain** | `your-domain.com` | Public access point |

## 🗄️ Database Schema

**Complete Dify Database with 62 Tables:**

### Core Application Tables
- `apps` - Application definitions
- `app_model_configs` - Model configurations
- `conversations` - Chat conversations
- `messages` - Chat messages
- `workflows` - Workflow definitions
- `workflow_runs` - Workflow executions
- `workflow_node_executions` - Node execution details

### Dataset & Knowledge Base
- `datasets` - Knowledge base datasets
- `documents` - Document storage
- `document_segments` - Text segments for RAG
- `embeddings` - Vector embeddings
- `dataset_queries` - Query tracking
- `dataset_retriever_resources` - Retrieval results

### User & Account Management
- `accounts` - User accounts
- `tenants` - Multi-tenant support
- `tenant_account_joins` - User-tenant relationships
- `end_users` - Application end users
- `api_tokens` - API access tokens

### Tool & Plugin System
- `builtin_tool_providers` - Built-in tools
- `api_tool_providers` - Custom API tools
- `workflow_tool_providers` - Workflow tools
- `tool_model_invokes` - Tool usage tracking
- `installed_plugins` - Plugin management
- `plugin_bindings` - Plugin configurations

### Message System Extensions
- `message_feedbacks` - User feedback
- `message_files` - File attachments
- `message_annotations` - Message annotations
- `message_chains` - Message chains
- `message_agent_thoughts` - Agent reasoning

### And 40+ more tables for complete functionality!

## 🚀 Quick Start

### 1. Deploy Infrastructure

```bash
# Clone repository
git clone https://github.com/your-username/dify-gcp.git
cd dify-gcp

# Deploy with Terraform
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Initialize Database

```bash
# SSH to instance and run database initialization
gcloud compute ssh your-project-dify-instance --zone=your-zone

# Run complete database setup
sudo /opt/dify/scripts/init-database.sh
```

### 3. Configure Email (Optional)

```bash
# Run email configuration script
sudo /opt/dify/scripts/setup-email.sh gmail your-email@gmail.com your-app-password

# Test email configuration
docker exec dify-api-1 python3 /opt/dify/test-email.py your-test@email.com
```

### 4. Access Your Dify Instance

🌐 **URL:** https://your-domain.com  
👤 **Admin:** `admin@dify.local`  
🔑 **Password:** `your-admin-password`

## 📧 Email Configuration

Supports multiple email providers with automated configuration:

### Supported Providers
- **Gmail** - `smtp.gmail.com:587` (TLS)
- **Outlook** - `smtp-mail.outlook.com:587` (TLS)
- **QQ Mail** - `smtp.qq.com:587` (TLS)
- **163 Mail** - `smtp.163.com:465` (SSL)
- **126 Mail** - `smtp.126.com:465` (SSL)
- **Custom SMTP** - Any SMTP server

### Setup Email

```bash
# Interactive setup
./scripts/setup-email.sh

# Direct setup
./scripts/setup-email.sh gmail admin@example.com app_password

# Test configuration
docker exec dify-api-1 python3 /opt/dify/test-email.py test@example.com
```

## 🔧 Management Scripts

### Database Management

```bash
# Initialize complete database schema (62 tables)
./scripts/init-database.sh

# Backup database
./scripts/backup-database.sh

# Restore database
./scripts/restore-database.sh backup-file.sql
```

### Email Management

```bash
# Setup email configuration
./scripts/setup-email.sh [provider] [email] [password]

# Test email connectivity
./scripts/test-email.sh [recipient]
```

### Service Management

```bash
# Update Dify to latest version
./scripts/update-dify.sh

# Setup SSL certificates
./scripts/setup-ssl.sh

# Monitor system status
./scripts/monitor-system.sh
```

## 🏷️ Environment Variables

### Core Configuration

```bash
# Application
MODE=production
LOG_LEVEL=INFO
SECRET_KEY=your-secret-key

# Database
DB_USERNAME=dify
DB_PASSWORD=your-db-password
DB_HOST=cloud-sql-proxy
DB_PORT=5432
DB_DATABASE=dify

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=difyredis123
REDIS_PORT=6379

# Web
CONSOLE_API_URL=https://your-domain.com
APP_API_URL=https://your-domain.com
```

### Email Configuration

```bash
# SMTP Settings
MAIL_TYPE=smtp
MAIL_DEFAULT_SEND_FROM=admin@your-domain.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=admin@your-domain.com
SMTP_PASSWORD=your-app-password
SMTP_USE_TLS=true
SMTP_USE_SSL=false

# Features
ENABLE_EMAIL_CODE_LOGIN=true
ENABLE_EMAIL_PASSWORD_LOGIN=true
SYSTEM_EMAIL_TEMPLATE_ENABLED=true
```

## 🎯 API Endpoints

### Health & Status

- `GET /health` - System health check
- `GET /console/api/setup` - Setup status
- `GET /console/api/workspaces/current` - Current workspace

### Authentication

- `POST /console/api/login` - Admin login
- `POST /console/api/setup` - Initial setup

### Application Management

- `GET /console/api/apps` - List applications
- `POST /console/api/apps` - Create application
- `GET /console/api/apps/{id}` - Get application details

### Dataset Management

- `GET /console/api/datasets` - List datasets
- `POST /console/api/datasets` - Create dataset
- `GET /console/api/datasets/{id}` - Get dataset details

## 🛡️ Security Features

### SSL/TLS Configuration
- **SSL Certificates:** Let's Encrypt via Certbot
- **TLS Version:** TLS 1.2+ only
- **HSTS:** Enabled with 1 year max-age
- **Certificate Auto-Renewal:** Automated

### Database Security
- **Connection:** SSL-encrypted connections
- **Authentication:** Username/password + IP restrictions
- **Backup Encryption:** AES-256 encryption
- **Access Control:** Role-based permissions

### Application Security
- **Authentication:** JWT tokens with rotation
- **Session Management:** Redis-backed sessions
- **API Rate Limiting:** Configurable limits
- **Input Validation:** Comprehensive sanitization

## 📊 Monitoring & Logs

### System Monitoring

```bash
# Check system resources
docker stats

# View application logs
docker logs dify-api-1 --tail 100

# Monitor database connections
docker exec dify-api-1 python3 -c "
import psycopg2
conn = psycopg2.connect(host='DB_HOST', port=DB_PORT, dbname='DB_NAME', user='DB_USER', password='DB_PASSWORD')
print('Database connection: OK')
"

# Check Redis connectivity
docker exec dify-redis-1 redis-cli ping
```

### Log Locations

- **Application Logs:** `docker logs dify-api-1`
- **Database Logs:** Cloud SQL console
- **Nginx Logs:** `docker logs dify-nginx-1`
- **System Logs:** `/var/log/` on VM instance

## 🚨 Troubleshooting

### Common Issues

#### 1. Database Connection Issues

```bash
# Check Cloud SQL proxy
docker exec dify-api-1 nc -z cloud-sql-proxy 5432

# Verify credentials
grep DB_ /opt/dify/.env

# Test database connection
docker exec dify-api-1 python3 -c "
import psycopg2
conn = psycopg2.connect(host='DB_HOST', port=DB_PORT, dbname='DB_NAME', user='DB_USER', password='DB_PASSWORD')
print('Connection successful')
"
```

#### 2. Email Not Working

```bash
# Test email configuration
docker exec dify-api-1 python3 /opt/dify/test-email.py

# Check SMTP settings
grep SMTP /opt/dify/.env

# Verify email credentials
# For Gmail: Use App Password, not regular password
```

#### 3. Load Balancer Issues

```bash
# Check health check endpoint
curl -I https://your-domain.com/health

# Verify backend health
gcloud compute backend-services get-health your-project-dify-backend --global

# Check instance group
gcloud compute instance-groups list-instances your-project-dify-instance-group --zone=your-zone
```

#### 4. Application Startup Issues

```bash
# Check all containers
docker ps -a

# Restart services
cd /opt/dify
docker-compose restart

# Check service logs
docker-compose logs api
```

## 🔄 Updates & Maintenance

### Update Dify

```bash
# Backup before update
./scripts/backup-database.sh

# Update to latest version
./scripts/update-dify.sh

# Verify update
curl -s https://your-domain.com/console/api/setup
```

### Database Maintenance

```bash
# Run database cleanup
docker exec dify-api-1 python3 -c "
import psycopg2
conn = psycopg2.connect(host='DB_HOST', port=DB_PORT, dbname='DB_NAME', user='DB_USER', password='DB_PASSWORD')
cur = conn.cursor()
cur.execute('VACUUM ANALYZE;')
conn.commit()
print('Database maintenance completed')
"
```

### SSL Certificate Renewal

```bash
# Renew certificates (auto-renewed)
certbot renew --nginx

# Check certificate expiry
openssl x509 -in /etc/letsencrypt/live/your-domain.com/cert.pem -text -noout | grep "Not After"
```

## 📞 Support

### Getting Help

1. **Check Logs:** Start with application and system logs
2. **Run Diagnostics:** Use built-in diagnostic scripts
3. **Community:** Dify GitHub Issues and Discussions
4. **Documentation:** Official Dify documentation

### Useful Commands

```bash
# System status overview
./scripts/system-status.sh

# Complete health check
./scripts/health-check.sh

# Generate diagnostic report
./scripts/diagnostic-report.sh
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🌟 Features

- ✅ **Production-Ready:** Complete infrastructure setup
- ✅ **Scalable:** Load balancer with auto-scaling support
- ✅ **Secure:** SSL/TLS, database encryption, security best practices
- ✅ **Complete Schema:** All 62 database tables for full functionality
- ✅ **Email Integration:** Multi-provider email support with testing
- ✅ **Monitoring:** Comprehensive logging and monitoring
- ✅ **Backup & Recovery:** Automated backup systems
- ✅ **Documentation:** Extensive documentation and troubleshooting guides

---

## 🎯 Quick Access

| Resource | URL/Command |
|----------|-------------|
| **Application** | https://your-domain.com |
| **Admin Login** | admin@dify.local / your-admin-password |
| **SSH Access** | `gcloud compute ssh your-project-dify-instance --zone=your-zone` |
| **Database Access** | `docker exec -it dify-api-1 python3` |
| **Logs** | `docker logs dify-api-1 --tail 100` |
| **Status** | `docker ps` |

**🚀 Your complete Dify deployment is ready for production use!**
