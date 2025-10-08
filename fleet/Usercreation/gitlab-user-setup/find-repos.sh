#!/bin/bash

# GitLab Repository Finder
# This script helps you find repository information for the config

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="${1:-config.yaml}"

echo -e "${BLUE}=== GitLab Repository Finder ===${NC}"

# Function to load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file ${CONFIG_FILE} not found${NC}"
        exit 1
    fi
    
    GITLAB_URL=$(yq eval '.gitlab.url' "$CONFIG_FILE")
    GITLAB_TOKEN=$(yq eval '.gitlab.token' "$CONFIG_FILE")
}

# Function to list all repositories
list_all_repos() {
    echo -e "${YELLOW}Fetching all repositories...${NC}"
    
    local response
    response=$(curl -s -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects?per_page=100&membership=true")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Found repositories:${NC}"
        echo ""
        echo "Format: ID | Name | Path | Web URL"
        echo "----------------------------------------"
        echo "$response" | jq -r '.[] | "\(.id) | \(.name) | \(.path_with_namespace) | \(.web_url)"'
    else
        echo -e "${RED}✗ Failed to fetch repositories${NC}"
    fi
}

# Function to search for specific repositories
search_repos() {
    local search_term="$1"
    
    if [ -z "$search_term" ]; then
        echo -e "${YELLOW}Enter search term: ${NC}"
        read -p "Search for: " search_term
    fi
    
    echo -e "${YELLOW}Searching for repositories containing: ${search_term}${NC}"
    
    local response
    response=$(curl -s -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects?search=${search_term}&per_page=100")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Search results:${NC}"
        echo ""
        echo "Format: ID | Name | Path | Web URL"
        echo "----------------------------------------"
        echo "$response" | jq -r '.[] | "\(.id) | \(.name) | \(.path_with_namespace) | \(.web_url)"'
    else
        echo -e "${RED}✗ Search failed${NC}"
    fi
}

# Function to get repository by path
get_repo_by_path() {
    local repo_path="$1"
    
    if [ -z "$repo_path" ]; then
        echo -e "${YELLOW}Enter repository path (e.g., group/project): ${NC}"
        read -p "Repository path: " repo_path
    fi
    
    echo -e "${YELLOW}Getting repository: ${repo_path}${NC}"
    
    # URL encode the path
    local encoded_path
    encoded_path=$(echo "$repo_path" | sed 's|/|%2F|g')
    
    local response
    response=$(curl -s -H "Authorization: Bearer ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects/${encoded_path}")
    
    if [ $? -eq 0 ]; then
        local repo_id
        repo_id=$(echo "$response" | jq -r '.id')
        if [ "$repo_id" != "null" ]; then
            echo -e "${GREEN}✓ Found repository:${NC}"
            echo "ID: $repo_id"
            echo "Name: $(echo "$response" | jq -r '.name')"
            echo "Path: $(echo "$response" | jq -r '.path_with_namespace')"
            echo "Web URL: $(echo "$response" | jq -r '.web_url')"
        else
            echo -e "${RED}✗ Repository not found${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to get repository${NC}"
    fi
}

# Function to show configuration examples
show_config_examples() {
    echo -e "${YELLOW}Configuration Examples:${NC}"
    echo ""
    echo "1. By repository name (searches all projects):"
    echo "   - name: \"frontend-app\""
    echo ""
    echo "2. By full project path:"
    echo "   - name: \"my-group/backend-api\""
    echo ""
    echo "3. By project ID:"
    echo "   - name: \"123\""
    echo ""
    echo "4. By full GitLab URL path:"
    echo "   - name: \"my-org/my-group/mobile-app\""
    echo ""
    echo "5. Multiple repositories:"
    echo "   repositories:"
    echo "     - name: \"my-group/frontend\""
    echo "       access_level: 30"
    echo "     - name: \"my-group/backend\""
    echo "       access_level: 30"
    echo "     - name: \"456\"  # Project ID"
    echo "       access_level: 40"
}

# Function to generate config snippet
generate_config_snippet() {
    echo -e "${YELLOW}Enter repository information to generate config snippet:${NC}"
    echo ""
    
    local repos=()
    local access_levels=()
    
    while true; do
        echo -e "${BLUE}Repository ${#repos[@] + 1}:${NC}"
        read -p "Repository name/path/ID: " repo_name
        read -p "Access level (10=Guest, 20=Reporter, 30=Developer, 40=Maintainer, 50=Owner): " access_level
        
        repos+=("$repo_name")
        access_levels+=("$access_level")
        
        echo ""
        read -p "Add another repository? (y/n): " add_more
        if [ "$add_more" != "y" ]; then
            break
        fi
    done
    
    echo -e "${GREEN}Generated config snippet:${NC}"
    echo "repositories:"
    for i in "${!repos[@]}"; do
        echo "  - name: \"${repos[$i]}\""
        echo "    access_level: ${access_levels[$i]}"
    done
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}What would you like to do?${NC}"
    echo "1. List all repositories"
    echo "2. Search repositories"
    echo "3. Get repository by path"
    echo "4. Show configuration examples"
    echo "5. Generate config snippet"
    echo "6. Exit"
    echo ""
    read -p "Enter your choice (1-6): " choice
    
    case $choice in
        1) list_all_repos ;;
        2) search_repos ;;
        3) get_repo_by_path ;;
        4) show_config_examples ;;
        5) generate_config_snippet ;;
        6) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; show_menu ;;
    esac
}

# Main execution
main() {
    load_config
    show_menu
}

# Run main function
main "$@"