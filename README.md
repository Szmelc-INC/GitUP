# GitUP
Back your shit with Git &lt;3

### Single-file short version
```bash
#!/bin/bash

# --- CONFIG ---
GIT_USER="user"
GIT_EMAIL="user@gmail.com"
GITHUB_USER="user"
GITHUB_TOKEN="ghp_2u..."
REPO_URL="github.com/user/repo.git"
DIR="/full/path/to/backup"
BRANCH="main"
# --------------

cd "$DIR"

# Initialize git repo if needed
if [ ! -d ".git" ]; then
    git init
fi

# Set git config locally
git config user.name "$GIT_USER"
git config user.email "$GIT_EMAIL"

# Configure remote with authentication
if git remote | grep -q origin; then
    git remote set-url origin "https://$GITHUB_USER:$GITHUB_TOKEN@$REPO_URL"
else
    git remote add origin "https://$GITHUB_USER:$GITHUB_TOKEN@$REPO_URL"
fi

# Ensure branch exists and checkout
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git checkout "$BRANCH"
else
    git checkout -b "$BRANCH"
fi

# Perform backup
git add .
git commit -m "Backup $(date '+%Y-%m-%d %H:%M:%S')"
git push -u origin "$BRANCH"
```
