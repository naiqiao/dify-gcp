#!/bin/bash

# =============================================================================
# Dify Email Configuration Script
# =============================================================================
# This script configures email settings for Dify including SMTP setup
# and email testing functionality
# 
# Usage: ./scripts/setup-email.sh [provider] [email] [password]
# Example: ./scripts/setup-email.sh gmail admin@example.com app_password
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PROVIDER="gmail"
ENV_FILE="/opt/dify/.env"

echo -e "${BLUE}📧 Dify Email Configuration Setup${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if running inside instance
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env file not found at $ENV_FILE${NC}"
    echo "This script should be run on the Dify instance."
    exit 1
fi

# Function to get email provider settings
get_provider_config() {
    local provider="$1"
    
    case "$provider" in
        "gmail")
            SMTP_SERVER="smtp.gmail.com"
            SMTP_PORT="587"
            SMTP_USE_TLS="true"
            SMTP_USE_SSL="false"
            echo -e "${GREEN}✓ Gmail configuration selected${NC}"
            ;;
        "outlook"|"hotmail")
            SMTP_SERVER="smtp-mail.outlook.com"
            SMTP_PORT="587"
            SMTP_USE_TLS="true"
            SMTP_USE_SSL="false"
            echo -e "${GREEN}✓ Outlook/Hotmail configuration selected${NC}"
            ;;
        "qq")
            SMTP_SERVER="smtp.qq.com"
            SMTP_PORT="587"
            SMTP_USE_TLS="true"
            SMTP_USE_SSL="false"
            echo -e "${GREEN}✓ QQ Mail configuration selected${NC}"
            ;;
        "163")
            SMTP_SERVER="smtp.163.com"
            SMTP_PORT="465"
            SMTP_USE_TLS="false"
            SMTP_USE_SSL="true"
            echo -e "${GREEN}✓ 163 Mail configuration selected${NC}"
            ;;
        "126")
            SMTP_SERVER="smtp.126.com"
            SMTP_PORT="465"
            SMTP_USE_TLS="false"
            SMTP_USE_SSL="true"
            echo -e "${GREEN}✓ 126 Mail configuration selected${NC}"
            ;;
        "custom")
            echo -e "${YELLOW}📝 Custom SMTP configuration${NC}"
            read -p "SMTP Server: " SMTP_SERVER
            read -p "SMTP Port: " SMTP_PORT
            read -p "Use TLS (true/false): " SMTP_USE_TLS
            read -p "Use SSL (true/false): " SMTP_USE_SSL
            ;;
        *)
            echo -e "${RED}❌ Unsupported provider: $provider${NC}"
            echo "Supported providers: gmail, outlook, qq, 163, 126, custom"
            exit 1
            ;;
    esac
}

# Function to update environment file
update_env_file() {
    local email="$1"
    local password="$2"
    
    echo -e "${YELLOW}📝 Updating .env file...${NC}"
    
    # Backup existing .env file
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove existing email configuration
    sed -i '/^# ===== EMAIL CONFIGURATION =====/,/^$/d' "$ENV_FILE"
    
    # Add new email configuration
    cat >> "$ENV_FILE" << EOF

# ===== EMAIL CONFIGURATION =====
# Email服务配置 - 自动生成于 $(date)

# 通用SMTP设置
MAIL_TYPE=smtp
MAIL_DEFAULT_SEND_FROM=$email
SMTP_SERVER=$SMTP_SERVER
SMTP_PORT=$SMTP_PORT
SMTP_USE_TLS=$SMTP_USE_TLS
SMTP_USERNAME=$email
SMTP_PASSWORD=$password

# 邮件发送功能开关
ENABLE_EMAIL_CODE_LOGIN=true
ENABLE_EMAIL_PASSWORD_LOGIN=true
MAIL_USE_TLS=$SMTP_USE_TLS
MAIL_USE_SSL=$SMTP_USE_SSL

# 系统邮件模板设置
SYSTEM_EMAIL_TEMPLATE_ENABLED=true

EOF
    
    echo -e "${GREEN}✓ .env file updated successfully${NC}"
}

# Function to create email test script
create_test_script() {
    local test_script="/opt/dify/test-email.py"
    
    echo -e "${YELLOW}📝 Creating email test script...${NC}"
    
    cat > "$test_script" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dify Email Configuration Test Script
用于测试Dify的邮件配置是否正常工作
"""

import smtplib
import sys
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os

def load_env_config():
    """从.env文件加载邮件配置"""
    config = {}
    try:
        with open('/opt/dify/.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key] = value
    except Exception as e:
        print(f'Error loading .env file: {e}')
        return None
    return config

def test_email_connection(config):
    """测试邮件服务器连接"""
    try:
        smtp_server = config.get('SMTP_SERVER', 'smtp.gmail.com')
        smtp_port = int(config.get('SMTP_PORT', '587'))
        smtp_username = config.get('SMTP_USERNAME', '')
        smtp_password = config.get('SMTP_PASSWORD', '')
        smtp_use_tls = config.get('SMTP_USE_TLS', 'true').lower() == 'true'
        smtp_use_ssl = config.get('SMTP_USE_SSL', 'false').lower() == 'true'
        
        print(f'📧 Testing email connection...')
        print(f'   SMTP Server: {smtp_server}')
        print(f'   Port: {smtp_port}')
        print(f'   Username: {smtp_username}')
        print(f'   Use TLS: {smtp_use_tls}')
        print(f'   Use SSL: {smtp_use_ssl}')
        print()
        
        if not smtp_username or smtp_password in ['your_email_app_password', '']:
            print('❌ Error: Please configure SMTP_USERNAME and SMTP_PASSWORD in .env file')
            return False
        
        # Create SMTP connection
        if smtp_use_ssl:
            server = smtplib.SMTP_SSL(smtp_server, smtp_port)
        else:
            server = smtplib.SMTP(smtp_server, smtp_port)
            if smtp_use_tls:
                server.starttls()
        
        # Login
        server.login(smtp_username, smtp_password)
        server.quit()
        
        print('✅ Email server connection successful!')
        return True
        
    except Exception as e:
        print(f'❌ Email connection failed: {e}')
        return False

def send_test_email(config, to_email):
    """发送测试邮件"""
    try:
        smtp_server = config.get('SMTP_SERVER', 'smtp.gmail.com')
        smtp_port = int(config.get('SMTP_PORT', '587'))
        smtp_username = config.get('SMTP_USERNAME', '')
        smtp_password = config.get('SMTP_PASSWORD', '')
        smtp_use_tls = config.get('SMTP_USE_TLS', 'true').lower() == 'true'
        smtp_use_ssl = config.get('SMTP_USE_SSL', 'false').lower() == 'true'
        from_email = config.get('MAIL_DEFAULT_SEND_FROM', smtp_username)
        
        # Create message
        msg = MIMEMultipart()
        msg['From'] = from_email
        msg['To'] = to_email
        msg['Subject'] = 'Dify Email Test - 邮件测试'
        
        body = '''
Hello! 你好！

This is a test email from your Dify installation.
这是来自你的Dify安装的测试邮件。

If you receive this email, your email configuration is working correctly!
如果你收到了这封邮件，说明你的邮件配置正常工作！

Configuration details:
- SMTP Server: {smtp_server}
- Port: {smtp_port}
- TLS: {smtp_use_tls}
- SSL: {smtp_use_ssl}

Best regards,
Dify System
        '''.format(
            smtp_server=smtp_server,
            smtp_port=smtp_port,
            smtp_use_tls=smtp_use_tls,
            smtp_use_ssl=smtp_use_ssl
        )
        
        msg.attach(MIMEText(body, 'plain', 'utf-8'))
        
        # Send email
        if smtp_use_ssl:
            server = smtplib.SMTP_SSL(smtp_server, smtp_port)
        else:
            server = smtplib.SMTP(smtp_server, smtp_port)
            if smtp_use_tls:
                server.starttls()
        
        server.login(smtp_username, smtp_password)
        server.send_message(msg)
        server.quit()
        
        print(f'✅ Test email sent successfully to {to_email}!')
        return True
        
    except Exception as e:
        print(f'❌ Failed to send test email: {e}')
        return False

def main():
    print('🔧 Dify Email Configuration Test')
    print('=' * 40)
    
    # Load configuration
    config = load_env_config()
    if not config:
        print('❌ Failed to load configuration')
        sys.exit(1)
    
    # Test connection
    if not test_email_connection(config):
        print()
        print('💡 Troubleshooting tips:')
        print('1. Check SMTP_USERNAME and SMTP_PASSWORD in .env file')
        print('2. For Gmail, use App Password instead of regular password')
        print('3. Verify SMTP server and port settings')
        sys.exit(1)
    
    # Optionally send test email
    if len(sys.argv) > 1:
        test_email = sys.argv[1]
        print()
        print(f'📧 Sending test email to {test_email}...')
        send_test_email(config, test_email)
    else:
        print()
        print('💡 To send a test email, run:')
        print('   python3 /opt/dify/test-email.py your-email@example.com')

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "$test_script"
    echo -e "${GREEN}✓ Email test script created at $test_script${NC}"
}

# Function to restart Dify services
restart_services() {
    echo -e "${YELLOW}🔄 Restarting Dify services...${NC}"
    
    cd /opt/dify
    docker-compose restart api worker
    
    echo -e "${GREEN}✓ Services restarted successfully${NC}"
}

# Main execution
main() {
    local provider="${1:-}"
    local email="${2:-}"
    local password="${3:-}"
    
    # Interactive mode if parameters not provided
    if [[ -z "$provider" ]]; then
        echo "Available email providers:"
        echo "  1. gmail (Gmail)"
        echo "  2. outlook (Outlook/Hotmail)"
        echo "  3. qq (QQ Mail)"
        echo "  4. 163 (163 Mail)"
        echo "  5. 126 (126 Mail)"
        echo "  6. custom (Custom SMTP)"
        echo
        read -p "Select email provider [1-6] or name: " provider_input
        
        case "$provider_input" in
            "1"|"gmail") provider="gmail" ;;
            "2"|"outlook") provider="outlook" ;;
            "3"|"qq") provider="qq" ;;
            "4"|"163") provider="163" ;;
            "5"|"126") provider="126" ;;
            "6"|"custom") provider="custom" ;;
            *) provider="$provider_input" ;;
        esac
    fi
    
    if [[ -z "$email" ]]; then
        read -p "Enter your email address: " email
    fi
    
    if [[ -z "$password" ]]; then
        read -s -p "Enter your email password (or app password): " password
        echo
    fi
    
    # Validate inputs
    if [[ -z "$provider" || -z "$email" || -z "$password" ]]; then
        echo -e "${RED}❌ Error: Missing required parameters${NC}"
        echo "Usage: $0 [provider] [email] [password]"
        exit 1
    fi
    
    # Get provider configuration
    get_provider_config "$provider"
    
    # Update environment file
    update_env_file "$email" "$password"
    
    # Create test script
    create_test_script
    
    # Restart services
    restart_services
    
    echo
    echo -e "${GREEN}🎉 Email configuration completed successfully!${NC}"
    echo
    echo "📋 Configuration Summary:"
    echo "========================="
    echo "Provider: $provider"
    echo "SMTP Server: $SMTP_SERVER"
    echo "Port: $SMTP_PORT"
    echo "Email: $email"
    echo "TLS: $SMTP_USE_TLS"
    echo "SSL: $SMTP_USE_SSL"
    echo
    echo "🧪 Test your email configuration:"
    echo "================================="
    echo "1. Test connection only:"
    echo "   docker exec dify-api-1 python3 /opt/dify/test-email.py"
    echo
    echo "2. Send test email:"
    echo "   docker exec dify-api-1 python3 /opt/dify/test-email.py your-email@example.com"
    echo
    echo -e "${BLUE}📧 Email setup complete! Your Dify instance can now send emails.${NC}"
}

# Run main function with all arguments
main "$@" 