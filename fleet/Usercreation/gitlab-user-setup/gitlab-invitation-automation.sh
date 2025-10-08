#!/bin/bash

# GitLab Repository Invitation Automation
# This script invites users to repositories via email invitations only
# Users will create accounts when they accept the invitations

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
LOG_FILE="gitlab-invitation-automation.log"

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
    
    # Load user emails (only emails needed for invitations)
    USER_EMAILS=($(yq eval '.users[].email' "$CONFIG_FILE"))
    
    # Load repositories
    REPOS=($(yq eval '.repositories[].name' "$CONFIG_FILE"))
    REPO_ACCESS_LEVELS=($(yq eval '.repositories[].access_level' "$CONFIG_FILE"))
    
    log "${GREEN}✓ Configuration loaded${NC}"
    log "${BLUE}GitLab URL: ${GITLAB_URL}${NC}"
    log "${BLUE}User emails: ${#USER_EMAILS[@]}${NC}"
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

# Function to invite user to repository by email
invite_user_to_repo() {
    local email="$1"
    local repo_id="$2"
    local access_level="$3"
    
    log "${PURPLE}Inviting ${email} to repository ${repo_id} with access level ${access_level}${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}DRY RUN: Would invite ${email} to repository ${repo_id}${NC}"
        return 0
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/gitlab_response.json \
        -X POST \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${email}\",
            \"access_level\": ${access_level}
        }" \
        "${GITLAB_URL}/api/v4/projects/${repo_id}/members")
    
    if [ "$response" = "201" ]; then
        log "${GREEN}✓ Invitation sent successfully to ${email}${NC}"
    elif [ "$response" = "409" ]; then
        log "${YELLOW}⚠ User ${email} is already a member of this repository${NC}"
    elif [ "$response" = "422" ]; then
        local error_msg
        error_msg=$(jq -r '.message' /tmp/gitlab_response.json 2>/dev/null || echo "Unknown error")
        log "${YELLOW}⚠ Invitation validation failed for ${email}: ${error_msg}${NC}"
    else
        log "${RED}✗ Failed to invite ${email} to repository (HTTP ${response})${NC}"
        cat /tmp/gitlab_response.json 2>/dev/null || echo "No response body"
        return 1
    fi
}

# Function to invite all users to all repositories
invite_all_users_to_all_repos() {
    log "${YELLOW}Inviting all users to all repositories...${NC}"
    
    for i in "${!REPOS[@]}"; do
        local repo_name="${REPOS[$i]}"
        local access_level="${REPO_ACCESS_LEVELS[$i]}"
        
        log "${BLUE}Processing repository: ${repo_name}${NC}"
        
        local repo_id
        repo_id=$(get_repo_id "$repo_name")
        
        if [ $? -eq 0 ]; then
            for email in "${USER_EMAILS[@]}"; do
                invite_user_to_repo "$email" "$repo_id" "$access_level"
                # Small delay to avoid rate limiting
                sleep 0.5
            done
        else
            log "${RED}✗ Skipping repository ${repo_name} due to error${NC}"
        fi
    done
    
    log "${GREEN}✓ All repository invitations processed${NC}"
}

# Function to show summary
show_summary() {
    log "${GREEN}=== GitLab Invitation Automation Summary ===${NC}"
    log "${BLUE}User emails: ${#USER_EMAILS[@]}${NC}"
    log "${BLUE}Repositories: ${#REPOS[@]}${NC}"
    log "${BLUE}Total invitations: $((${#USER_EMAILS[@]} * ${#REPOS[@]}))${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}This was a dry run. No invitations were sent.${NC}"
    else
        log "${GREEN}Invitation automation completed successfully!${NC}"
        log "${YELLOW}Users will receive email invitations and can create accounts when they accept.${NC}"
    fi
}

# Function to cleanup
cleanup() {
    rm -f /tmp/gitlab_response.json
}

# Main execution
main() {
    log "${GREEN}=== GitLab Repository Invitation Automation ===${NC}"
    log "${BLUE}Configuration file: ${CONFIG_FILE}${NC}"
    log "${BLUE}Dry run mode: ${DRY_RUN}${NC}"
    
    check_prerequisites
    load_config
    test_gitlab_connection
    
    # Invite all users to all repositories
    invite_all_users_to_all_repos
    
    # Show summary
    show_summary
    
    # Cleanup
    cleanup
}

# Run main function
main "$@"
