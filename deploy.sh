#!/bin/bash

# =========================================
# DevOps Stage 1 - Automated Deployment Script
# Author: Oluyemi Boluwatife Peter
# =========================================

set -e  # exit immediately if a command fails
set -o pipefail

# ---- VARIABLES ----
LOG_FILE="deploy_$(date +%Y%m%d).log"

# Trap function for unexpected errors
trap 'echo "[ERROR] Something went wrong. Check $LOG_FILE for details." | tee -a $LOG_FILE; exit 1' ERR

echo "===============================" | tee -a $LOG_FILE
echo "🚀 DevOps Deployment Started at $(date)" | tee -a $LOG_FILE
echo "===============================" | tee -a $LOG_FILE

# ---- STEP 1: Collect Parameters ----
read -p "Enter your Git repository URL: " GIT_URL
read -p "Enter your Personal Access Token (PAT): " PAT
read -p "Enter branch name (default: main): " BRANCH
read -p "Enter SSH username: " SSH_USER
read -p "Enter server IP address: " SERVER_IP
read -p "Enter SSH key path (e.g., ~/.ssh/id_rsa): " SSH_KEY
read -p "Enter internal application port (e.g., 3000): " APP_PORT

BRANCH=${BRANCH:-main}

# ---- STEP 2: Clone Repository ----
REPO_NAME=$(basename -s .git "$GIT_URL")

if [ -d "$REPO_NAME" ]; then
  echo "[INFO] Repository exists. Pulling latest changes..." | tee -a $LOG_FILE
  cd "$REPO_NAME" && git pull origin "$BRANCH"
else
  echo "[INFO] Cloning repository..." | tee -a $LOG_FILE
  GIT_AUTH_URL=$(echo "$GIT_URL" | sed "s#https://#https://$PAT@#")
  git clone -b "$BRANCH" "$GIT_AUTH_URL"
  cd "$REPO_NAME"
fi

# ---- STEP 3: Verify Docker setup ----
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  echo "[ERROR] No Dockerfile or docker-compose.yml found in repository." | tee -a $LOG_FILE
  exit 1
else
  echo "[SUCCESS] Docker configuration found." | tee -a $LOG_FILE
fi

# ---- STEP 4: SSH Connectivity Check ----
echo "[INFO] Checking SSH connection..." | tee -a $LOG_FILE
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo 'SSH Connection Successful!'" | tee -a $LOG_FILE

# ---- STEP 5: Prepare Remote Environment ----
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
set -e
echo "[INFO] Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

echo "[INFO] Installing Docker and Nginx..."
sudo apt install -y docker.io docker-compose nginx

sudo systemctl enable docker --now
sudo systemctl enable nginx --now

sudo usermod -aG docker $USER || true
docker --version
nginx -v
EOF

# ---- STEP 6: Deploy the Application ----
echo "[INFO] Copying project files to remote server..." | tee -a $LOG_FILE
scp -i "$SSH_KEY" -r . "$SSH_USER@$SERVER_IP:/home/$SSH_USER/$REPO_NAME"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
cd ~/$REPO_NAME

if [ -f docker-compose.yml ]; then
  echo "[INFO] Running docker-compose deployment..."
  sudo docker-compose down || true
  sudo docker-compose up -d --build
else
  echo "[INFO] Running Docker build and run..."
  sudo docker build -t myapp .
  sudo docker run -d -p 80:$APP_PORT myapp
fi
EOF

# ---- STEP 7: Configure Nginx ----
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<EOF
cat <<NGINX | sudo tee /etc/nginx/sites-available/$REPO_NAME
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF

# ---- STEP 8: Validate Deployment ----
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -I localhost" | tee -a $LOG_FILE

echo "✅ Deployment completed successfully!" | tee -a $LOG_FILE

