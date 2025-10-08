#!/bin/bash

# GitLab Setup Helper Script
# This script helps you set up the GitLab automation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GitLab User and Repository Automation Setup ===${NC}"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed${NC}"
        echo "Install jq:"
        echo "  macOS: brew install jq"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is not installed${NC}"
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        echo -e "${YELLOW}Installing yq...${NC}"
        install_yq
    fi
    
    echo -e "${GREEN}✓ Prerequisites check passed${NC}"
}

# Function to install yq
install_yq() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install yq
        else
            echo -e "${RED}Error: Please install yq manually: https://github.com/mikefarah/yq${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x /usr/local/bin/yq
    else
        echo -e "${RED}Error: Unsupported OS. Please install yq manually: https://github.com/mikefarah/yq${NC}"
        exit 1
    fi
}

# Function to create GitLab token
create_gitlab_token() {
    echo -e "${YELLOW}Creating GitLab Personal Access Token...${NC}"
    echo ""
    echo "1. Go to your GitLab instance: ${GITLAB_URL}"
    echo "2. Click on your avatar (top right)"
    echo "3. Go to 'Preferences' > 'Access Tokens'"
    echo "4. Create a new token with these scopes:"
    echo "   - api (Full API access)"
    echo "   - read_user (Read user information)"
    echo "   - read_repository (Read repository information)"
    echo "5. Copy the token and paste it below"
    echo ""
    read -p "Enter your GitLab token: " GITLAB_TOKEN
    
    if [ -n "$GITLAB_TOKEN" ]; then
        # Update config file with token
        yq eval ".gitlab.token = \"${GITLAB_TOKEN}\"" -i config.yaml
        echo -e "${GREEN}✓ Token saved to config.yaml${NC}"
    else
        echo -e "${RED}Error: No token provided${NC}"
        exit 1
    fi
}

# Function to test GitLab connection
test_gitlab_connection() {
    echo -e "${YELLOW}Testing GitLab connection...${NC}"
    
    local response
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/user")
    
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}✓ GitLab connection successful${NC}"
    else
        echo -e "${RED}✗ GitLab connection failed (HTTP ${response})${NC}"
        echo "Please check your GitLab URL and token"
        exit 1
    fi
}

# Function to list existing repositories
list_repositories() {
    echo -e "${YELLOW}Fetching existing repositories...${NC}"
    
    local response
    response=$(curl -s -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects?per_page=100")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Found repositories:${NC}"
        echo "$response" | jq -r '.[] | "\(.name) (\(.id))"'
    else
        echo -e "${RED}✗ Failed to fetch repositories${NC}"
    fi
}

# Function to list existing users
list_users() {
    echo -e "${YELLOW}Fetching existing users...${NC}"
    
    local response
    response=$(curl -s -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/users?per_page=100")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Found users:${NC}"
        echo "$response" | jq -r '.[] | "\(.username) (\(.name)) - \(.email)"'
    else
        echo -e "${RED}✗ Failed to fetch users${NC}"
    fi
}

# Function to run dry run
run_dry_run() {
    echo -e "${YELLOW}Running dry run...${NC}"
    ./gitlab-automation.sh config.yaml true
}

# Function to run automation
run_automation() {
    echo -e "${YELLOW}Running GitLab automation...${NC}"
    ./gitlab-automation.sh config.yaml false
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}What would you like to do?${NC}"
    echo "1. Check prerequisites"
    echo "2. Configure GitLab token"
    echo "3. Test GitLab connection"
    echo "4. List existing repositories"
    echo "5. List existing users"
    echo "6. Find repository information"
    echo "7. Run dry run (preview changes)"
    echo "8. Run automation (create users and invite to repos)"
    echo "9. Exit"
    echo ""
    read -p "Enter your choice (1-9): " choice
    
    case $choice in
        1) check_prerequisites ;;
        2) create_gitlab_token ;;
        3) test_gitlab_connection ;;
        4) list_repositories ;;
        5) list_users ;;
        6) ./find-repos.sh ;;
        7) run_dry_run ;;
        8) run_automation ;;
        9) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; show_menu ;;
    esac
}

# Load configuration
load_config() {
    if [ -f "config.yaml" ]; then
        GITLAB_URL=$(yq eval '.gitlab.url' config.yaml)
        GITLAB_TOKEN=$(yq eval '.gitlab.token' config.yaml)
    else
        echo -e "${RED}Error: config.yaml not found${NC}"
        exit 1
    fi
}

# Main execution
main() {
    load_config
    show_menu
}

# Run main function
main "$@"