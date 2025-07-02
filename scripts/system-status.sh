#!/bin/bash

# =============================================================================
# Dify System Status Check Script
# =============================================================================
# This script performs a comprehensive health check of the Dify deployment
# including database, services, email, and infrastructure components
# 
# Usage: ./scripts/system-status.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Icons
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"

echo -e "${BLUE}🔍 Dify System Status Check${NC}"
echo -e "${BLUE}===========================${NC}"
echo "Timestamp: $(date)"
echo

# Function to test component status
check_component() {
    local component="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "  Testing $component... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}${CHECK}${NC}"
        return 0
    else
        echo -e "${RED}${CROSS}${NC}"
        return 1
    fi
}

# Function to get component info
get_info() {
    local component="$1"
    local command="$2"
    
    echo -n "  $component: "
    local result=$(eval "$command" 2>/dev/null || echo "N/A")
    echo -e "${YELLOW}$result${NC}"
}

# 1. INFRASTRUCTURE STATUS
echo -e "${PURPLE}🏗️  Infrastructure Status${NC}"
echo "========================="

# Check if we're on the correct instance
if [[ -f "/opt/dify/.env" ]]; then
    echo -e "  ${CHECK} Running on Dify instance"
else
    echo -e "  ${CROSS} Not running on Dify instance"
    exit 1
fi

# Check system resources
get_info "CPU Usage" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1"
get_info "Memory Usage" "free -h | awk '/^Mem:/ {print \$3\"/\"\$2\" (\"\$3/\$2*100\"%)\"}'| cut -d'(' -f2 | cut -d')' -f1"
get_info "Disk Usage" "df -h /opt/dify | tail -1 | awk '{print \$5}'"
get_info "System Uptime" "uptime -p"

echo

# 2. DOCKER SERVICES STATUS
echo -e "${PURPLE}🐳 Docker Services Status${NC}"
echo "=========================="

cd /opt/dify 2>/dev/null || { echo -e "${RED}${CROSS} Cannot access /opt/dify${NC}"; exit 1; }

# Check Docker daemon
check_component "Docker Daemon" "docker info" "running"

# Check Docker Compose services
services=("nginx" "api" "worker" "web" "redis" "cloud-sql-proxy")
for service in "${services[@]}"; do
    if docker-compose ps | grep -q "${service}.*Up"; then
        echo -e "  ${CHECK} dify-${service}-1 running"
    else
        echo -e "  ${CROSS} dify-${service}-1 not running"
    fi
done

echo

# 3. DATABASE CONNECTIVITY
echo -e "${PURPLE}🗄️  Database Status${NC}"
echo "==================="

# Test database connection
if docker exec dify-api-1 python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(
        host='cloud-sql-proxy',
        port=5432,
        dbname='dify',
        user='dify',
        password='your-db-password'
    )
    cur = conn.cursor()
    cur.execute('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \'public\';')
    table_count = cur.fetchone()[0]
    print(f'✅ Database connected - {table_count} tables')
    cur.close()
    conn.close()
except Exception as e:
    print(f'❌ Database connection failed: {e}')
    exit(1)
" 2>/dev/null; then
    echo -e "  ${CHECK} Database connectivity verified"
else
    echo -e "  ${CROSS} Database connection failed"
fi

# Check Cloud SQL proxy
check_component "Cloud SQL Proxy" "docker exec dify-cloud-sql-proxy-1 netstat -tlnp | grep :5432" "listening"

echo

# 4. REDIS STATUS
echo -e "${PURPLE}🔴 Redis Status${NC}"
echo "==============="

# Test Redis connection
if docker exec dify-redis-1 redis-cli ping | grep -q "PONG"; then
    echo -e "  ${CHECK} Redis connectivity verified"
else
    echo -e "  ${CROSS} Redis connection failed"
fi

# Get Redis info
get_info "Redis Version" "docker exec dify-redis-1 redis-cli info server | grep redis_version | cut -d: -f2 | tr -d '\r'"
get_info "Redis Memory" "docker exec dify-redis-1 redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r'"

echo

# 5. WEB SERVICE STATUS
echo -e "${PURPLE}🌐 Web Service Status${NC}"
echo "====================="

# Test health endpoint
if curl -s -f http://localhost/health | grep -q "healthy"; then
    echo -e "  ${CHECK} Internal health check passed"
else
    echo -e "  ${CROSS} Internal health check failed"
fi

# Test external access
if curl -s -f https://your-domain.com/health | grep -q "healthy"; then
    echo -e "  ${CHECK} External health check passed"
else
    echo -e "  ${CROSS} External health check failed"
fi

# Check API endpoints
api_endpoints=(
    "/console/api/setup"
    "/console/api/workspaces/current"
    "/console/api/apps"
)

for endpoint in "${api_endpoints[@]}"; do
    if curl -s -f "https://your-domain.com$endpoint" &>/dev/null; then
        echo -e "  ${CHECK} API endpoint $endpoint accessible"
    else
        echo -e "  ${WARNING} API endpoint $endpoint not accessible (may require auth)"
    fi
done

echo

# 6. SSL CERTIFICATE STATUS
echo -e "${PURPLE}🔒 SSL Certificate Status${NC}"
echo "========================="

# Check certificate expiry
if command -v openssl &>/dev/null; then
    if cert_info=$(echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
        echo -e "  ${CHECK} SSL certificate valid"
        echo "$cert_info" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    else
        echo -e "  ${CROSS} SSL certificate check failed"
    fi
else
    echo -e "  ${WARNING} OpenSSL not available for certificate check"
fi

echo

# 7. EMAIL CONFIGURATION STATUS
echo -e "${PURPLE}📧 Email Configuration Status${NC}"
echo "============================="

# Check email configuration in .env
if grep -q "SMTP_SERVER" /opt/dify/.env; then
    echo -e "  ${CHECK} Email configuration found"
    
    # Extract email settings
    smtp_server=$(grep "SMTP_SERVER=" /opt/dify/.env | cut -d'=' -f2)
    smtp_port=$(grep "SMTP_PORT=" /opt/dify/.env | cut -d'=' -f2)
    smtp_username=$(grep "SMTP_USERNAME=" /opt/dify/.env | cut -d'=' -f2)
    
    echo -e "    ${YELLOW}SMTP Server: $smtp_server${NC}"
    echo -e "    ${YELLOW}SMTP Port: $smtp_port${NC}"
    echo -e "    ${YELLOW}SMTP Username: $smtp_username${NC}"
    
    # Test email connectivity if test script exists
    if [[ -f "/opt/dify/test-email.py" ]]; then
        echo -e "  ${INFO} Run 'docker exec dify-api-1 python3 /opt/dify/test-email.py' to test email"
    else
        echo -e "  ${WARNING} Email test script not found"
    fi
else
    echo -e "  ${CROSS} Email configuration not found"
fi

echo

# 8. RESOURCE USAGE SUMMARY
echo -e "${PURPLE}📊 Resource Usage Summary${NC}"
echo "========================="

# Docker container stats
echo -e "  ${INFO} Container Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -7

echo

# 9. LOG SUMMARY
echo -e "${PURPLE}📋 Recent Logs Summary${NC}"
echo "======================"

# Check for recent errors in API logs
if docker logs dify-api-1 --since="1h" --tail=50 2>/dev/null | grep -i error | head -3; then
    echo -e "  ${WARNING} Recent errors found in API logs (showing last 3):"
    docker logs dify-api-1 --since="1h" --tail=50 2>/dev/null | grep -i error | head -3 | while read line; do
        echo -e "    ${RED}$line${NC}"
    done
else
    echo -e "  ${CHECK} No recent errors in API logs"
fi

echo

# 10. SYSTEM SUMMARY
echo -e "${PURPLE}📈 System Summary${NC}"
echo "================="

# Count running services
running_services=$(docker ps | grep -c "dify-.*Up" || echo "0")
total_services=6

echo -e "  ${INFO} Services Status: $running_services/$total_services running"

# Database table count
table_count=$(docker exec dify-api-1 python3 -c "
import psycopg2
conn = psycopg2.connect(host='DB_HOST', port=DB_PORT, dbname='DB_NAME', user='DB_USER', password='DB_PASSWORD')
cur = conn.cursor()
cur.execute('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"public\";')
print(cur.fetchone()[0])
conn.close()
" 2>/dev/null || echo "0")

echo -e "  ${INFO} Database Tables: $table_count/62 created"

# Overall status
if [[ $running_services -eq $total_services ]] && [[ $table_count -eq 62 ]]; then
    echo -e "  ${CHECK} ${GREEN}Overall Status: HEALTHY${NC}"
else
    echo -e "  ${WARNING} ${YELLOW}Overall Status: NEEDS ATTENTION${NC}"
fi

echo

# 11. QUICK ACTIONS
echo -e "${PURPLE}🚀 Quick Actions${NC}"
echo "================"

echo "  Common commands:"
echo -e "    ${YELLOW}View API logs:${NC} docker logs dify-api-1 --tail 50"
echo -e "    ${YELLOW}Restart services:${NC} docker-compose restart"
echo -e "    ${YELLOW}Check database:${NC} docker exec dify-api-1 python3 -c \"import psycopg2; print('DB OK')\""
echo -e "    ${YELLOW}Test email:${NC} docker exec dify-api-1 python3 /opt/dify/test-email.py"
echo -e "    ${YELLOW}Update Dify:${NC} ./scripts/update-dify.sh"

echo
echo -e "${BLUE}📋 Status check completed at $(date)${NC}"
echo -e "${GREEN}🎯 Access your Dify instance at: https://your-domain.com${NC}" 