# 🔒 Security Guidelines

## Sensitive Information

This repository contains example configuration files. **Never commit actual credentials or sensitive information.**

### Files to Keep Private

- `.env` - Contains database passwords, API keys, etc.
- `terraform.tfvars` - Contains GCP project details
- `*.key`, `*.pem` - SSH keys and certificates
- Any backup files containing real data

### What's Safe to Commit

- `.env.example` - Template with placeholder values
- `terraform.tfvars.example` - Template with example values
- Documentation and scripts (after cleanup)

## Before Contributing

1. **Review your changes** for sensitive information
2. **Use the cleanup script** if needed:
   ```bash
   ./cleanup-for-opensource.sh
   ```
3. **Check git history** for accidentally committed secrets
4. **Test with example values** to ensure functionality

## Reporting Security Issues

If you find security vulnerabilities, please report them privately to the maintainers rather than creating public issues.

## Security Best Practices

1. **Use strong passwords** for all accounts
2. **Enable 2FA** on cloud accounts
3. **Regularly rotate** API keys and passwords
4. **Monitor access logs** for suspicious activity
5. **Keep software updated** regularly
6. **Use HTTPS** for all web traffic
7. **Backup regularly** and test restore procedures

## Default Credentials

The deployment uses these default credentials that **must be changed**:

- Admin username: `admin@dify.local`
- Admin password: Change from default immediately
- Database password: Set in `.env` file
- Redis password: Set in `.env` file

## Infrastructure Security

- VPC network isolation
- Firewall rules (HTTP/HTTPS/SSH only)
- Service account with minimal permissions
- Automatic SSL/TLS encryption
- Database encryption at rest
- Regular security updates via startup scripts

## Compliance

This deployment includes:

- HTTPS enforced for all traffic
- Database connection encryption
- Session management via Redis
- Access logging and monitoring
- Regular automated backups
