# GitLab Repository Invitation Automation

Automate inviting users to GitLab repositories via email invitations. Users will create accounts when they accept the invitations.

## 🎯 What This Does

- **Sends email invitations** to users for GitLab repositories
- **No user creation required** - users create accounts when accepting invitations
- **Only email addresses needed** - no usernames, names, or passwords required
- **Handles existing users** gracefully (won't send duplicate invitations)
- **Supports dry-run mode** for testing
- **Comprehensive logging** of all operations

## 📁 Files Overview

```
gitlab-user-setup/
├── gitlab-invitation-automation.sh  # Main invitation automation script
├── config-invitation.yaml            # Configuration file (email-only)
├── setup-gitlab.sh                   # Interactive setup helper
└── README-invitation.md              # This file
```

## 🚀 Quick Start

### 1. **Configure GitLab Access**
```bash
# Edit the configuration file
nano config-invitation.yaml

# Update these values:
# - gitlab.url: Your GitLab instance URL
# - gitlab.token: Your GitLab personal access token
```

### 2. **Update User Emails**
```yaml
users:
  - email: "alice.dev@yourcompany.com"
  - email: "bob.dev@yourcompany.com"
  - email: "charlie.dev@yourcompany.com"
  # ... add more emails as needed
```

### 3. **Run the Automation**
```bash
# Make script executable
chmod +x gitlab-invitation-automation.sh

# Dry run first (preview invitations)
./gitlab-invitation-automation.sh config-invitation.yaml true

# Send actual invitations
./gitlab-invitation-automation.sh config-invitation.yaml false
```

## 🔧 Configuration

### **GitLab Settings**
```yaml
gitlab:
  url: "https://gitlab.example.com"
  token: "your-gitlab-token-here"
```

### **Users (Email Addresses Only)**
```yaml
users:
  - email: "alice.dev@example.com"
  - email: "bob.dev@example.com"
  - email: "charlie.dev@example.com"
  - email: "diana.dev@example.com"
  - email: "eve.dev@example.com"
  - email: "frank.dev@example.com"
```

### **Repositories (All Developer Access)**
```yaml
repositories:
  - name: "frontend-app"
    access_level: 30  # Developer
  
  - name: "my-group/backend-api"
    access_level: 30  # Developer
  
  - name: "123"  # Project ID
    access_level: 30  # Developer
  
  - name: "devops-tools"
    access_level: 30  # Developer
  # ... more repositories
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

### **Dry Run (Preview)**
```bash
# Preview what invitations will be sent
./gitlab-invitation-automation.sh config-invitation.yaml true
```

### **Send Invitations**
```bash
# Send actual email invitations
./gitlab-invitation-automation.sh config-invitation.yaml false
```

### **Custom Configuration**
```bash
# Use different config file
./gitlab-invitation-automation.sh my-config.yaml false
```

## 🔍 What Happens

### **Email Invitations Sent**
- Each user receives email invitations for all repositories
- Users can accept invitations even if they don't have GitLab accounts yet
- When users accept invitations, they can create their GitLab accounts

### **Repository Access**
Each invited user gets access to all specified repositories with the configured access level:
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

4. **"User is already a member"**
   - This is normal - script handles existing members gracefully
   - No duplicate invitations will be sent

### **Debug Commands**

```bash
# Test GitLab connection
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/user"

# List existing repositories
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects"

# Check repository members
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects/PROJECT_ID/members"
```

## 📊 Monitoring

### **Check Sent Invitations**
```bash
# List members of a specific repository
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects/PROJECT_ID/members" | jq '.[] | {username: .username, email: .email, access_level: .access_level}'
```

### **Check Pending Invitations**
```bash
# List pending invitations for a repository
curl -H "Authorization: Bearer YOUR_TOKEN" "https://gitlab.example.com/api/v4/projects/PROJECT_ID/invitations"
```

## 🔐 Security Notes

- **Email Security**: Ensure email addresses are correct and secure
- **Token Security**: Keep your GitLab token secure and rotate regularly
- **Access Levels**: Review access levels to ensure appropriate permissions
- **Invitation Expiry**: GitLab invitations may expire after a certain time

## 🚨 Important Considerations

1. **Email Delivery**: Ensure users can receive emails from your GitLab instance
2. **Invitation Expiry**: Users must accept invitations within the expiry period
3. **Repository Existence**: Ensure all repositories exist before running
4. **Permissions**: Ensure your token has sufficient permissions to invite users
5. **Rate Limits**: GitLab has API rate limits - script handles this with delays

## 📈 Advanced Usage

### **Custom Email Configuration**
Edit `config-invitation.yaml` to modify:
- User email addresses
- Repository names and access levels
- GitLab instance URL and token

### **Batch Processing**
The script processes all users and repositories with small delays to avoid rate limits.

### **Error Handling**
The script continues processing even if individual invitations fail, providing detailed error messages.

## 🔄 Comparison with User Creation Approach

| Feature | User Creation | Email Invitations |
|---------|---------------|-------------------|
| **Setup Complexity** | High (username, email, name, password) | Low (email only) |
| **User Control** | Full control over usernames/passwords | Users choose their own |
| **Immediate Access** | Yes | No (requires email acceptance) |
| **Email Dependency** | No | Yes |
| **Bulk Operations** | Yes | Yes |
| **User Experience** | Immediate access | Requires email interaction |

---

**⚠️ Warning**: This script sends real email invitations. Always test with a dry run first and ensure you have appropriate permissions.
