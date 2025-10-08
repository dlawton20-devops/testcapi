#!/bin/bash

# GitLab User and Repository Invitation Automation
# This script creates 6 users and invites them to 10 repositories

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE="${1:-config.yaml}"
DRY_RUN="${2:-false}"
LOG_FILE="gitlab-automation.log"

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "${YELLOW}Checking prerequisites...${NC}"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log "${RED}Error: jq is not installed. Please install jq first.${NC}"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log "${RED}Error: curl is not installed. Please install curl first.${NC}"
        exit 1
    fi
    
    # Check if yq is installed (for YAML parsing)
    if ! command -v yq &> /dev/null; then
        log "${YELLOW}Warning: yq is not installed. Installing yq...${NC}"
        install_yq
    fi
    
    log "${GREEN}✓ Prerequisites check passed${NC}"
}

# Function to install yq
install_yq() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install yq
        else
            log "${RED}Error: Please install yq manually: https://github.com/mikefarah/yq${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x /usr/local/bin/yq
    else
        log "${RED}Error: Unsupported OS. Please install yq manually: https://github.com/mikefarah/yq${NC}"
        exit 1
    fi
}

# Function to load configuration
load_config() {
    log "${YELLOW}Loading configuration from ${CONFIG_FILE}...${NC}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log "${RED}Error: Configuration file ${CONFIG_FILE} not found${NC}"
        exit 1
    fi
    
    # Load GitLab configuration
    GITLAB_URL=$(yq eval '.gitlab.url' "$CONFIG_FILE")
    GITLAB_TOKEN=$(yq eval '.gitlab.token' "$CONFIG_FILE")
    
    # Load users
    USERS=($(yq eval '.users[].username' "$CONFIG_FILE"))
    USER_EMAILS=($(yq eval '.users[].email' "$CONFIG_FILE"))
    USER_NAMES=($(yq eval '.users[].name' "$CONFIG_FILE"))
    USER_PASSWORDS=($(yq eval '.users[].password' "$CONFIG_FILE"))
    
    # Load repositories
    REPOS=($(yq eval '.repositories[].name' "$CONFIG_FILE"))
    REPO_ACCESS_LEVELS=($(yq eval '.repositories[].access_level' "$CONFIG_FILE"))
    
    log "${GREEN}✓ Configuration loaded${NC}"
    log "${BLUE}GitLab URL: ${GITLAB_URL}${NC}"
    log "${BLUE}Users: ${#USERS[@]}${NC}"
    log "${BLUE}Repositories: ${#REPOS[@]}${NC}"
}

# Function to test GitLab connection
test_gitlab_connection() {
    log "${YELLOW}Testing GitLab connection...${NC}"
    
    local response
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/user")
    
    if [ "$response" = "200" ]; then
        log "${GREEN}✓ GitLab connection successful${NC}"
    else
        log "${RED}✗ GitLab connection failed (HTTP ${response})${NC}"
        log "${RED}Please check your GitLab URL and token${NC}"
        exit 1
    fi
}

# Function to create a user
create_user() {
    local username="$1"
    local email="$2"
    local name="$3"
    local password="$4"
    
    log "${PURPLE}Creating user: ${username}${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}DRY RUN: Would create user ${username} (${email})${NC}"
        return 0
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
        -X POST \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${username}\",
            \"email\": \"${email}\",
            \"name\": \"${name}\",
            \"password\": \"${password}\",
            \"skip_confirmation\": true,
            \"can_create_group\": false,
            \"can_create_project\": false
        }" \
        "${GITLAB_URL}/api/v4/users")
    
    if [ "$response" = "201" ]; then
        local user_id
        user_id=$(jq -r '.id' /tmp/gitlab_response.json)
        log "${GREEN}✓ User created successfully: ${username} (ID: ${user_id})${NC}"
        echo "$user_id"
    elif [ "$response" = "422" ]; then
        local error_msg
        error_msg=$(jq -r '.message' /tmp/gitlab_response.json 2>/dev/null || echo "Unknown error")
        log "${YELLOW}⚠ User ${username} already exists or validation failed: ${error_msg}${NC}"
        # Try to get existing user ID
        get_user_id "$username"
    else
        log "${RED}✗ Failed to create user ${username} (HTTP ${response})${NC}"
        cat /tmp/gitlab_response.json 2>/dev/null || echo "No response body"
        return 1
    fi
}

# Function to get existing user ID
get_user_id() {
    local username="$1"
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/users?username=${username}")
    
    if [ "$response" = "200" ]; then
        local user_id
        user_id=$(jq -r '.[0].id' /tmp/gitlab_response.json)
        if [ "$user_id" != "null" ]; then
            log "${GREEN}✓ Found existing user: ${username} (ID: ${user_id})${NC}"
            echo "$user_id"
        else
            log "${RED}✗ User ${username} not found${NC}"
            return 1
        fi
    else
        log "${RED}✗ Failed to get user ID for ${username} (HTTP ${response})${NC}"
        return 1
    fi
}

# Function to get repository ID
get_repo_id() {
    local repo_name="$1"
    
    # Check if it's a numeric project ID
    if [[ "$repo_name" =~ ^[0-9]+$ ]]; then
        log "${GREEN}✓ Using project ID: ${repo_name}${NC}"
        echo "$repo_name"
        return 0
    fi
    
    # Check if it's a full path (contains /)
    if [[ "$repo_name" == *"/"* ]]; then
        # URL encode the path
        local encoded_path
        encoded_path=$(echo "$repo_name" | sed 's|/|%2F|g')
        
        local response
        response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
            -H "Authorization: Bearer ${GITLAB_TOKEN}" \
            "${GITLAB_URL}/api/v4/projects/${encoded_path}")
        
        if [ "$response" = "200" ]; then
            local repo_id
            repo_id=$(jq -r '.id' /tmp/gitlab_response.json)
            if [ "$repo_id" != "null" ]; then
                log "${GREEN}✓ Found repository by path: ${repo_name} (ID: ${repo_id})${NC}"
                echo "$repo_id"
                return 0
            fi
        fi
    fi
    
    # Fallback to search by name
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects?search=${repo_name}")
    
    if [ "$response" = "200" ]; then
        local repo_id
        repo_id=$(jq -r '.[0].id' /tmp/gitlab_response.json)
        if [ "$repo_id" != "null" ]; then
            log "${GREEN}✓ Found repository by search: ${repo_name} (ID: ${repo_id})${NC}"
            echo "$repo_id"
        else
            log "${RED}✗ Repository ${repo_name} not found${NC}"
            return 1
        fi
    else
        log "${RED}✗ Failed to get repository ID for ${repo_name} (HTTP ${response})${NC}"
        return 1
    fi
}

# Function to invite user to repository
invite_user_to_repo() {
    local user_id="$1"
    local repo_id="$2"
    local access_level="$3"
    
    log "${PURPLE}Inviting user ${user_id} to repository ${repo_id} with access level ${access_level}${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}DRY RUN: Would invite user ${user_id} to repository ${repo_id}${NC}"
        return 0
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
        -X POST \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"user_id\": ${user_id},
            \"access_level\": ${access_level}
        }" \
        "${GITLAB_URL}/api/v4/projects/${repo_id}/members")
    
    if [ "$response" = "201" ]; then
        log "${GREEN}✓ User invited successfully to repository${NC}"
    elif [ "$response" = "409" ]; then
        log "${YELLOW}⚠ User is already a member of this repository${NC}"
    else
        log "${RED}✗ Failed to invite user to repository (HTTP ${response})${NC}"
        cat /tmp/gitlab_response.json 2>/dev/null || echo "No response body"
        return 1
    fi
}

# Function to create all users
create_all_users() {
    log "${YELLOW}Creating all users...${NC}"
    
    local user_ids=()
    
    for i in "${!USERS[@]}"; do
        local username="${USERS[$i]}"
        local email="${USER_EMAILS[$i]}"
        local name="${USER_NAMES[$i]}"
        local password="${USER_PASSWORDS[$i]}"
        
        local user_id
        user_id=$(create_user "$username" "$email" "$name" "$password")
        user_ids+=("$user_id")
    done
    
    log "${GREEN}✓ All users processed${NC}"
    echo "${user_ids[@]}"
}

# Function to invite users to all repositories
invite_to_all_repos() {
    local user_ids=("$@")
    
    log "${YELLOW}Inviting users to all repositories...${NC}"
    
    for i in "${!REPOS[@]}"; do
        local repo_name="${REPOS[$i]}"
        local access_level="${REPO_ACCESS_LEVELS[$i]}"
        
        log "${BLUE}Processing repository: ${repo_name}${NC}"
        
        local repo_id
        repo_id=$(get_repo_id "$repo_name")
        
        if [ $? -eq 0 ]; then
            for user_id in "${user_ids[@]}"; do
                invite_user_to_repo "$user_id" "$repo_id" "$access_level"
            done
        else
            log "${RED}✗ Skipping repository ${repo_name} due to error${NC}"
        fi
    done
    
    log "${GREEN}✓ All repository invitations processed${NC}"
}

# Function to show summary
show_summary() {
    log "${GREEN}=== GitLab Automation Summary ===${NC}"
    log "${BLUE}Users processed: ${#USERS[@]}${NC}"
    log "${BLUE}Repositories processed: ${#REPOS[@]}${NC}"
    log "${BLUE}Total invitations: $((${#USERS[@]} * ${#REPOS[@]}))${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}This was a dry run. No changes were made.${NC}"
    else
        log "${GREEN}Automation completed successfully!${NC}"
    fi
}

# Function to cleanup
cleanup() {
    rm -f /tmp/gitlab_response.json
}

# Main execution
main() {
    log "${GREEN}=== GitLab User and Repository Automation ===${NC}"
    log "${BLUE}Configuration file: ${CONFIG_FILE}${NC}"
    log "${BLUE}Dry run mode: ${DRY_RUN}${NC}"
    
    check_prerequisites
    load_config
    test_gitlab_connection
    
    # Create users
    local user_ids
    user_ids=($(create_all_users))
    
    # Invite users to repositories
    invite_to_all_repos "${user_ids[@]}"
    
    # Show summary
    show_summary
    
    # Cleanup
    cleanup
}

# Run main function
main "$@"