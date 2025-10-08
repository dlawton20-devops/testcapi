# GitLab User and Repository Automation

Automate creating 6 users and inviting them to 10 GitLab repositories with a single script.

## 🎯 What This Does

- **Creates 6 users** in GitLab with specified usernames, emails, and passwords
- **Invites all users** to 10 repositories with appropriate access levels
- **Handles existing users** gracefully (won't create duplicates)
- **Supports dry-run mode** for testing
- **Comprehensive logging** of all operations

## 📁 Files Overview

```
gitlab-user-setup/
├── gitlab-automation.sh    # Main automation script
├── setup-gitlab.sh         # Interactive setup helper
├── config.yaml             # Configuration file
└── README.md               # This file
```

## 🚀 Quick Start

### 1. **Configure GitLab Access**
```bash
# Edit the configuration file
nano config.yaml

# Update these values:
# - gitlab.url: Your GitLab instance URL
# - gitlab.token: Your GitLab personal access token
```

### 2. **Run the Setup Helper**
```bash
./setup-gitlab.sh
```

### 3. **Find Repository Information**
```bash
# Interactive repository finder
./find-repos.sh
```

### 4. **Or Run Directly**
```bash
# Dry run first (preview changes)
./gitlab-automation.sh config.yaml true

# Apply changes
./gitlab-automation.sh config.yaml false
```

## 🔧 Configuration

### **GitLab Settings**
```yaml
gitlab:
  url: "https://gitlab.example.com"
  token: "your-gitlab-token-here"
```

### **Users (6 users)**
```yaml
users:
  - username: "alice-dev"
    email: "alice.dev@example.com"
    name: "Alice Developer"
    password: "SecurePassword123!"
  # ... 5 more users
```

### **Repositories (10 repos) - All Developer Access**
```yaml
repositories:
  # Option 1: By repository name (searches all projects)
  - name: "frontend-app"
    access_level: 30  # Developer
  
  # Option 2: By full project path (group/project)
  - name: "my-group/backend-api"
    access_level: 30  # Developer
  
  # Option 3: By project ID (numeric ID)
  - name: "123"  # Project ID
    access_level: 30  # Developer
  
  # Option 4: By full GitLab URL path
  - name: "my-org/my-group/mobile-app"
    access_level: 30  # Developer
  
  # All repositories get Developer access (level 30)
  - name: "devops-tools"
    access_level: 30  # Developer
  - name: "documentation"
    access_level: 30  # Developer
  - name: "testing-framework"
    access_level: 30  # Developer
  - name: "shared-libraries"
    access_level: 30  # Developer
  - name: "infrastructure"
    access_level: 30  # Developer
  - name: "monitoring"
    access_level: 30  # Developer
  - name: "security-tools"
    access_level: 30  # Developer
```

## 🔍 Repository Specification Methods

### **1. By Repository Name (Searches All Projects)**
```yaml
- name: "frontend-app"
  access_level: 30
```
- Searches all projects for repositories with this name
- Use when you have unique repository names

### **2. By Full Project Path**
```yaml
- name: "my-group/backend-api"
  access_level: 30
```
- Specifies the exact group and project path
- Most reliable method

### **3. By Project ID**
```yaml
- name: "123"
  access_level: 30
```
- Uses the numeric project ID
- Fastest method, but IDs can change

### **4. By Full GitLab URL Path**
```yaml
- name: "my-org/my-group/mobile-app"
  access_level: 30
```
- Includes organization, group, and project
- Use for complex nested structures

## 🔑 Access Levels

| Level | Value | Description |
|-------|-------|-------------|
| Guest | 10 | Can view issues and merge requests |
| Reporter | 20 | Can view and download code |
| Developer | 30 | Can push to non-protected branches |
| Maintainer | 40 | Can push to protected branches |
| Owner | 50 | Full access to project |

## 🛠️ Prerequisites

### **Required Tools**
- `curl` - For API calls
- `jq` - For JSON parsing
- `yq` - For YAML parsing

### **Installation**
```bash
# macOS
brew install jq yq

# Ubuntu/Debian
sudo apt-get install jq
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# CentOS/RHEL
sudo yum install jq
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq
```

### **GitLab Token**
Create a Personal Access Token with these scopes:
- `api` - Full API access
- `read_user` - Read user information
- `read_repository` - Read repository information

## 📋 Usage Examples

### **Interactive Setup**
```bash
./setup-gitlab.sh
```

### **Direct Execution**
```bash
# Preview what will be created
./gitlab-automation.sh config.yaml true

# Create users and invite to repositories
./gitlab-automation.sh config.yaml false
```

### **Custom Configuration**
```bash
# Use different config file
./gitlab-automation.sh my-config.yaml false
```

## 🔍 What Gets Created

### **Users Created**
- `alice-dev` - Alice Developer
- `bob-dev` - Bob Developer
- `charlie-dev` - Charlie Developer
- `diana-dev` - Diana Developer
- `eve-dev` - Eve Developer
- `frank-dev` - Frank Developer

### **Repository Access**
Each user gets invited to all 10 repositories with **Developer access** (level 30):
- `frontend-app` (Developer access)
- `backend-api` (Developer access)
- `mobile-app` (Developer access)
- `devops-tools` (Developer access)
- `documentation` (Developer access)
- `testing-framework` (Developer access)
- `shared-libraries` (Developer access)
- `infrastructure` (Developer access)
- `monitoring` (Developer access)
- `security-tools` (Developer access)

## 🐛 Troubleshooting

### **Common Issues**

1. **"jq not found"**
   ```bash
   # Install jq
   brew install jq  # macOS
   sudo apt-get install jq  # Ubuntu
   ```

2. **"yq not found"**
   ```bash
   # Install yq
   brew install yq  # macOS
   wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
   chmod +x /usr/local/bin/yq
   ```

3. **"GitLab connection failed"**
   - Check your GitLab URL
   - Verify your token has correct permissions
   - Ensure GitLab is accessible

4. **"User already exists"**
   - This is normal - script handles existing users gracefully
   - Users will be invited to repositories even if they already exist

### **Debug Commands**

```bash
# Test GitLab connection
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/user"

# List existing users
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/users"

# List existing repositories
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects"
```

## 📊 Monitoring

### **Check Created Users**
```bash
# List all users
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/users" | jq '.[] | {username: .username, name: .name, email: .email}'
```

### **Check Repository Members**
```bash
# List members of a specific repository
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects/PROJECT_ID/members" | jq '.[] | {username: .username, access_level: .access_level}'
```

## 🔐 Security Notes

- **Strong Passwords**: Use strong, unique passwords for each user
- **Token Security**: Keep your GitLab token secure and rotate regularly
- **Access Levels**: Review access levels to ensure appropriate permissions
- **User Management**: Consider using SSO for production environments

## 🚨 Important Considerations

1. **User Passwords**: Users will need to change passwords on first login
2. **Email Verification**: Users may need to verify their email addresses
3. **Repository Existence**: Ensure all repositories exist before running
4. **Permissions**: Ensure your token has sufficient permissions
5. **Rate Limits**: GitLab has API rate limits - script handles this gracefully

## 📈 Advanced Usage

### **Custom User Configuration**
Edit `config.yaml` to modify:
- User usernames, emails, names, passwords
- Repository names and access levels
- GitLab instance URL and token

### **Batch Processing**
The script processes all users and repositories in batches to avoid rate limits.

### **Error Handling**
The script continues processing even if individual operations fail, providing detailed error messages.

---

**⚠️ Warning**: This script creates real users and repository access. Always test with a dry run first and ensure you have appropriate permissions.