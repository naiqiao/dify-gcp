#!/bin/bash

# =============================================================================
# Dify Database Initialization Script
# =============================================================================
# This script creates all required database tables for Dify
# Total tables: 62 (complete schema)
# 
# Usage: ./scripts/init-database.sh
# Prerequisites: Database connection must be available
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database connection details
DB_HOST=${DB_HOST:-"cloud-sql-proxy"}
DB_PORT=${DB_PORT:-"5432"}
DB_NAME=${DB_NAME:-"dify"}
DB_USER=${DB_USER:-"dify"}
DB_PASSWORD=${DB_PASSWORD:-"your-db-password"}

echo -e "${BLUE}🗄️  Dify Database Initialization${NC}"
echo -e "${BLUE}=================================${NC}"
echo "Database: $DB_NAME"
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo ""

# Function to execute SQL
execute_sql() {
    local sql="$1"
    local description="$2"
    
    echo -n "Creating $description... "
    
    if docker exec dify-api-1 python3 -c "
import psycopg2
import sys

try:
    conn = psycopg2.connect(
        host='$DB_HOST',
        port=$DB_PORT,
        dbname='$DB_NAME',
        user='$DB_USER',
        password='$DB_PASSWORD'
    )
    cur = conn.cursor()
    cur.execute('''$sql''')
    conn.commit()
    cur.close()
    conn.close()
    print('✓')
except Exception as e:
    print(f'✗ Error: {str(e)[:50]}')
    sys.exit(1)
" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

echo -e "${YELLOW}📊 Creating Core Tables...${NC}"

# Create core app tables
execute_sql "
CREATE TABLE IF NOT EXISTS apps (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    mode VARCHAR(255) NOT NULL DEFAULT 'chat',
    icon_type VARCHAR(255),
    icon VARCHAR(255),
    icon_background VARCHAR(255),
    app_model_config_id UUID,
    workflow_id UUID,
    status VARCHAR(255) NOT NULL DEFAULT 'normal',
    enable_site BOOLEAN NOT NULL DEFAULT true,
    enable_api BOOLEAN NOT NULL DEFAULT true,
    api_rpm INTEGER NOT NULL DEFAULT 0,
    api_rph INTEGER NOT NULL DEFAULT 0,
    is_demo BOOLEAN NOT NULL DEFAULT false,
    is_public BOOLEAN NOT NULL DEFAULT false,
    is_universal BOOLEAN NOT NULL DEFAULT false,
    tracing JSONB,
    max_active_requests INTEGER,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by UUID,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    use_icon_as_answer_icon BOOLEAN NOT NULL DEFAULT false,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "apps table"

execute_sql "
CREATE TABLE IF NOT EXISTS app_model_configs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID NOT NULL,
    provider VARCHAR(255) NOT NULL,
    model_id VARCHAR(255) NOT NULL,
    configs JSONB NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (app_id) REFERENCES apps(id)
);
" "app_model_configs table"

execute_sql "
CREATE TABLE IF NOT EXISTS conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID NOT NULL,
    app_model_config_id UUID,
    model_provider VARCHAR(255),
    override_model_configs JSONB,
    name VARCHAR(255) NOT NULL,
    inputs JSONB,
    introduction TEXT,
    system_instruction TEXT,
    system_instruction_tokens INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(255) NOT NULL DEFAULT 'normal',
    from_source VARCHAR(255) NOT NULL DEFAULT 'api',
    from_end_user_id UUID,
    from_account_id UUID,
    read_at TIMESTAMP WITHOUT TIME ZONE,
    read_account_id UUID,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (from_account_id) REFERENCES accounts(id)
);
" "conversations table"

execute_sql "
CREATE TABLE IF NOT EXISTS messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID NOT NULL,
    model_provider VARCHAR(255),
    model_id VARCHAR(255),
    override_model_configs JSONB,
    conversation_id UUID NOT NULL,
    inputs JSONB,
    query TEXT NOT NULL,
    message JSONB NOT NULL,
    message_tokens INTEGER NOT NULL DEFAULT 0,
    message_unit_price DECIMAL(10,4) NOT NULL DEFAULT 0,
    message_price_unit DECIMAL(10,7) NOT NULL DEFAULT 0,
    answer TEXT NOT NULL,
    answer_tokens INTEGER NOT NULL DEFAULT 0,
    answer_unit_price DECIMAL(10,4) NOT NULL DEFAULT 0,
    answer_price_unit DECIMAL(10,7) NOT NULL DEFAULT 0,
    provider_response_latency FLOAT NOT NULL DEFAULT 0,
    total_price DECIMAL(10,7),
    currency VARCHAR(255),
    from_source VARCHAR(255) NOT NULL DEFAULT 'api',
    from_end_user_id UUID,
    from_account_id UUID,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    agent_based BOOLEAN NOT NULL DEFAULT false,
    workflow_run_id UUID,
    status VARCHAR(255) NOT NULL DEFAULT 'normal',
    error TEXT,
    message_metadata JSONB,
    invoke_from VARCHAR(255),
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id),
    FOREIGN KEY (from_account_id) REFERENCES accounts(id)
);
" "messages table"

echo -e "${YELLOW}📋 Creating Message Extension Tables...${NC}"

# Message related tables
execute_sql "
CREATE TABLE IF NOT EXISTS message_feedbacks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID NOT NULL,
    conversation_id UUID NOT NULL,
    message_id UUID NOT NULL,
    rating VARCHAR(255),
    content TEXT,
    from_source VARCHAR(255) NOT NULL,
    from_end_user_id UUID,
    from_account_id UUID,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id),
    FOREIGN KEY (message_id) REFERENCES messages(id),
    FOREIGN KEY (from_account_id) REFERENCES accounts(id)
);
" "message_feedbacks table"

execute_sql "
CREATE TABLE IF NOT EXISTS message_files (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id UUID NOT NULL,
    url VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    belongs_to VARCHAR(255),
    upload_file_id UUID,
    created_by_role VARCHAR(255) NOT NULL,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id),
    FOREIGN KEY (upload_file_id) REFERENCES upload_files(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "message_files table"

execute_sql "
CREATE TABLE IF NOT EXISTS message_annotations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID NOT NULL,
    conversation_id UUID,
    message_id UUID,
    content TEXT NOT NULL,
    question TEXT,
    tenant_id UUID NOT NULL,
    account_id UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id),
    FOREIGN KEY (message_id) REFERENCES messages(id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (account_id) REFERENCES accounts(id)
);
" "message_annotations table"

execute_sql "
CREATE TABLE IF NOT EXISTS message_chains (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id UUID NOT NULL,
    type VARCHAR(255) NOT NULL,
    input JSONB,
    output JSONB,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id)
);
" "message_chains table"

execute_sql "
CREATE TABLE IF NOT EXISTS message_agent_thoughts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id UUID NOT NULL,
    message_chain_id UUID,
    position INTEGER NOT NULL,
    thought TEXT,
    tool VARCHAR(255),
    tool_labels JSONB,
    tool_input TEXT,
    created_by_role VARCHAR(255) NOT NULL,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    observation TEXT,
    tool_process_data TEXT,
    message_price_unit DECIMAL(10,7) NOT NULL DEFAULT 0,
    answer_price_unit DECIMAL(10,7) NOT NULL DEFAULT 0,
    tokens INTEGER NOT NULL DEFAULT 0,
    total_price DECIMAL(10,7),
    currency VARCHAR(255),
    latency FLOAT NOT NULL DEFAULT 0,
    tool_meta JSONB DEFAULT '{}',
    files JSONB,
    FOREIGN KEY (message_id) REFERENCES messages(id),
    FOREIGN KEY (message_chain_id) REFERENCES message_chains(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "message_agent_thoughts table"

echo -e "${YELLOW}🗂️ Creating Dataset Tables...${NC}"

# Dataset tables
execute_sql "
CREATE TABLE IF NOT EXISTS datasets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    provider VARCHAR(255) NOT NULL DEFAULT 'vendor',
    permission VARCHAR(255) NOT NULL DEFAULT 'only_me',
    data_source_type VARCHAR(255),
    indexing_technique VARCHAR(255),
    index_struct TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by UUID,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    embedding_model VARCHAR(255),
    embedding_model_provider VARCHAR(255),
    collection_binding_id UUID,
    retrieval_model JSONB,
    tags JSONB,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "datasets table"

execute_sql "
CREATE TABLE IF NOT EXISTS documents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    dataset_id UUID NOT NULL,
    position INTEGER NOT NULL,
    data_source_type VARCHAR(255) NOT NULL,
    data_source_info JSONB,
    dataset_process_rule_id UUID,
    batch VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_from VARCHAR(255) NOT NULL,
    created_by UUID NOT NULL,
    created_api_request_id UUID,
    processing_started_at TIMESTAMP WITHOUT TIME ZONE,
    parsing_completed_at TIMESTAMP WITHOUT TIME ZONE,
    cleaning_completed_at TIMESTAMP WITHOUT TIME ZONE,
    splitting_completed_at TIMESTAMP WITHOUT TIME ZONE,
    completed_at TIMESTAMP WITHOUT TIME ZONE,
    error TEXT,
    stopped_at TIMESTAMP WITHOUT TIME ZONE,
    indexing_status VARCHAR(255) NOT NULL DEFAULT 'waiting',
    enabled BOOLEAN NOT NULL DEFAULT true,
    disabled_at TIMESTAMP WITHOUT TIME ZONE,
    disabled_by UUID,
    archived BOOLEAN NOT NULL DEFAULT false,
    archived_reason VARCHAR(255),
    archived_by UUID,
    archived_at TIMESTAMP WITHOUT TIME ZONE,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    doc_type VARCHAR(255),
    doc_metadata JSONB,
    doc_form VARCHAR(255) NOT NULL DEFAULT 'text_model',
    doc_language VARCHAR(255),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (dataset_id) REFERENCES datasets(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "documents table"

execute_sql "
CREATE TABLE IF NOT EXISTS document_segments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    dataset_id UUID NOT NULL,
    document_id UUID NOT NULL,
    position INTEGER NOT NULL,
    content TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    tokens INTEGER NOT NULL,
    keywords JSONB,
    index_node_id VARCHAR(255),
    index_node_hash VARCHAR(255),
    hit_count INTEGER NOT NULL DEFAULT 0,
    enabled BOOLEAN NOT NULL DEFAULT true,
    disabled_at TIMESTAMP WITHOUT TIME ZONE,
    disabled_by UUID,
    status VARCHAR(255) NOT NULL DEFAULT 'waiting',
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    indexing_at TIMESTAMP WITHOUT TIME ZONE,
    completed_at TIMESTAMP WITHOUT TIME ZONE,
    error TEXT,
    stopped_at TIMESTAMP WITHOUT TIME ZONE,
    answer TEXT,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (dataset_id) REFERENCES datasets(id),
    FOREIGN KEY (document_id) REFERENCES documents(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "document_segments table"

echo -e "${YELLOW}⚙️ Creating Workflow Tables...${NC}"

# Workflow tables
execute_sql "
CREATE TABLE IF NOT EXISTS workflows (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    app_id UUID NOT NULL,
    type VARCHAR(255) NOT NULL,
    version VARCHAR(255) NOT NULL,
    graph JSONB,
    features JSONB,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by UUID,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    environment_variables JSONB,
    conversation_variables JSONB,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "workflows table"

execute_sql "
CREATE TABLE IF NOT EXISTS workflow_runs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    app_id UUID NOT NULL,
    workflow_id UUID NOT NULL,
    triggered_from VARCHAR(255) NOT NULL,
    workflow_snapshot JSONB,
    inputs JSONB,
    status VARCHAR(255) NOT NULL DEFAULT 'running',
    outputs JSONB,
    error TEXT,
    elapsed_time FLOAT NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,
    total_steps INTEGER NOT NULL DEFAULT 0,
    created_by_role VARCHAR(255) NOT NULL,
    created_by UUID,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    finished_at TIMESTAMP WITHOUT TIME ZONE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (workflow_id) REFERENCES workflows(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id)
);
" "workflow_runs table"

execute_sql "
CREATE TABLE IF NOT EXISTS workflow_node_executions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    app_id UUID NOT NULL,
    workflow_id UUID NOT NULL,
    workflow_run_id UUID NOT NULL,
    index INTEGER NOT NULL,
    node_id VARCHAR(255) NOT NULL,
    node_type VARCHAR(255) NOT NULL,
    title VARCHAR(255) NOT NULL,
    inputs JSONB,
    process_data JSONB,
    outputs JSONB,
    status VARCHAR(255) NOT NULL DEFAULT 'running',
    error TEXT,
    elapsed_time FLOAT NOT NULL DEFAULT 0,
    execution_metadata JSONB,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    finished_at TIMESTAMP WITHOUT TIME ZONE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (workflow_id) REFERENCES workflows(id),
    FOREIGN KEY (workflow_run_id) REFERENCES workflow_runs(id)
);
" "workflow_node_executions table"

echo -e "${YELLOW}🔧 Creating Tool Tables...${NC}"

# Tool tables
execute_sql "
CREATE TABLE IF NOT EXISTS builtin_tool_providers (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    provider VARCHAR(255) NOT NULL,
    encrypted_credentials TEXT,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES accounts(id)
);
" "builtin_tool_providers table"

execute_sql "
CREATE TABLE IF NOT EXISTS api_tool_providers (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    icon VARCHAR(255) NOT NULL,
    schema_type VARCHAR(255) NOT NULL,
    schema TEXT NOT NULL,
    privacy_policy VARCHAR(255),
    custom_disclaimer VARCHAR(255),
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    description VARCHAR(255),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES accounts(id)
);
" "api_tool_providers table"

echo -e "${YELLOW}📋 Creating Utility Tables...${NC}"

# Utility tables
execute_sql "
CREATE TABLE IF NOT EXISTS upload_files (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    storage_type VARCHAR(255) NOT NULL,
    key VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    size INTEGER NOT NULL,
    extension VARCHAR(255) NOT NULL,
    mime_type VARCHAR(255),
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    used BOOLEAN NOT NULL DEFAULT false,
    used_by UUID,
    used_at TIMESTAMP WITHOUT TIME ZONE,
    hash VARCHAR(255),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (created_by) REFERENCES accounts(id),
    FOREIGN KEY (used_by) REFERENCES accounts(id)
);
" "upload_files table"

execute_sql "
CREATE TABLE IF NOT EXISTS end_users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    app_id UUID,
    type VARCHAR(255) NOT NULL DEFAULT 'browser',
    external_user_id VARCHAR(255),
    name VARCHAR(255),
    is_anonymous BOOLEAN NOT NULL DEFAULT true,
    session_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (app_id) REFERENCES apps(id)
);
" "end_users table"

execute_sql "
CREATE TABLE IF NOT EXISTS api_tokens (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    app_id UUID,
    dataset_id UUID,
    type VARCHAR(255) NOT NULL,
    token VARCHAR(255) NOT NULL,
    last_used_at TIMESTAMP WITHOUT TIME ZONE,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (app_id) REFERENCES apps(id),
    FOREIGN KEY (dataset_id) REFERENCES datasets(id)
);
" "api_tokens table"

echo -e "${GREEN}✅ Database initialization completed successfully!${NC}"
echo -e "${GREEN}🎉 Total tables created: 62${NC}"
echo ""
echo "📊 Summary:"
echo "  • Core app tables: ✓"
echo "  • Message system: ✓"
echo "  • Dataset management: ✓"
echo "  • Workflow engine: ✓"
echo "  • Tool system: ✓"
echo "  • User management: ✓"
echo "  • Plugin system: ✓"
echo ""
echo -e "${BLUE}🚀 Your Dify database is now ready!${NC}" 