#!/usr/bin/env bash
set -uo pipefail

# -----------------------------
# SUDOERS CONFIG
# -----------------------------
CURRENT_USER=${SUDO_USER:-$USER}
echo "==> Configuring passwordless sudo for '$CURRENT_USER'..."
echo "$CURRENT_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$CURRENT_USER" > /dev/null
sudo chmod 0440 "/etc/sudoers.d/$CURRENT_USER"
sudo usermod -aG sudo "$USER"
#newgrp sudo

echo "==> Updating system..."
sudo apt update -y

echo "==> Installing base dependencies..."
sudo apt install -y \
  zsh git curl wget apt-transport-https ca-certificates gnupg lsb-release \
  vim fonts-powerline

# -----------------------------
# DOCKER INSTALL
# -----------------------------
echo "==> Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER || true

# -----------------------------
# KUBECTL
# -----------------------------
echo "==> Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# -----------------------------
# KUBECOLOR
# -----------------------------
echo "==> Installing kubecolor..."
wget https://github.com/kubecolor/kubecolor/releases/download/v0.6.0/kubecolor_0.6.0_linux_amd64.tar.gz
tar -xvzf kubecolor_0.6.0_linux_amd64.tar.gz kubecolor
sudo mv kubecolor /usr/local/bin/
sudo chmod +x /usr/local/bin/kubecolor
rm -f kubecolor_0.6.0_linux_amd64.tar.gz

# -----------------------------
# HELM
# -----------------------------
echo "==> Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# -----------------------------
# KUBECTX / KUBENS
# -----------------------------
echo "==> Installing kubectx & kubens..."
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx

sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens

# -----------------------------
# MINIKUBE
# -----------------------------
echo "==> Installing Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube
minikube addons enable metrics-server

# -----------------------------
# ALIAS FILE (EXTERNAL)
# -----------------------------
echo "==> Downloading alias file..."

sudo curl -fsSL \
"https://raw.githubusercontent.com/Aaron89893/Document/main/alias.verbose.txt" \
-o /usr/share/alias.verbose

# safe permission
sudo chmod 777 /usr/share/alias.verbose

# -----------------------------
# ZSH + OH-MY-ZSH + P10K
# -----------------------------
echo "==> Installing Zsh + Oh My Zsh..."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

# p10k
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k"
fi


# plugins
for repo in \
  https://github.com/zsh-users/zsh-autosuggestions \
  https://github.com/zsh-users/zsh-syntax-highlighting \
  https://github.com/marlonrichert/zsh-autocomplete
do
  name=$(basename "$repo")
  [ -d "$ZSH_CUSTOM/plugins/$name" ] || git clone --depth 1 "$repo" "$ZSH_CUSTOM/plugins/$name"
done

# -----------------------------
# ZSHRC CONFIG
# -----------------------------
echo "==> Configuring .zshrc..."

ZSHRC="$HOME/.zshrc"

grep -q "powerlevel10k" "$ZSHRC" || echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"

grep -q "POWERLEVEL9K_INSTANT_PROMPT" "$ZSHRC" || \
echo 'typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet' >> "$ZSHRC"


grep -q "alias.verbose" "$ZSHRC" || \
echo 'source /usr/share/alias.verbose' >> "$ZSHRC"

# Clean up old bash-specific kubectl completion in .zshrc if present
if [ -f "$ZSHRC" ]; then
  sed -i '/kubectl completion bash/d' "$ZSHRC"
  sed -i '/complete -o default -F __start_kubectl k/d' "$ZSHRC"
fi

grep -q "kubectl completion zsh" "$ZSHRC" || cat <<'EOF' >> "$ZSHRC"

# --- kubectl autocomplete ---
source <(kubectl completion zsh)
alias k=kubectl
compdef _kubectl k
EOF

grep -q "plugins=" "$ZSHRC" && \
sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC" || \
echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"

grep -q "zsh-syntax-highlighting.zsh" "$ZSHRC" || \
echo 'source ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "$ZSHRC"

grep -q "zsh-autosuggestions.zsh" "$ZSHRC" || \
echo 'source ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$ZSHRC"

grep -q "powerlevel10k.zsh-theme" "$ZSHRC" || \
echo 'source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme' >> "$ZSHRC"

# remove compinit if exists (required by zsh-autocomplete)
if [ -f "$ZSHRC" ]; then
  sed -i '/compinit/d' "$ZSHRC" || true
fi

grep -q "zsh-autocomplete.plugin.zsh" "$ZSHRC" || cat <<'EOF' >> "$ZSHRC"

# --- zsh-autocomplete (marlonrichert) ---
source ~/.oh-my-zsh/custom/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
EOF

# Disable global compinit in Ubuntu (recommended by author of zsh-autocomplete)
touch ~/.zshenv
grep -q "skip_global_compinit" ~/.zshenv || echo "skip_global_compinit=1" >> ~/.zshenv


# -----------------------------
# VIM CONFIG
# -----------------------------
echo "==> Configuring vim..."
cat <<'EOF' >> ~/.vimrc
set expandtab
set tabstop=2
set shiftwidth=2
set number
set autoindent
EOF

# -----------------------------
# ANSIBLE
# -----------------------------
echo "==> Installing Ansible..."

sudo apt update -y
sudo apt install -y software-properties-common

sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

# -----------------------------
# TERRAFORM
# -----------------------------
echo "==> Installing Terraform..."

sudo apt install -y gnupg software-properties-common curl

curl -fsSL https://apt.releases.hashicorp.com/gpg | \
sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo \
"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update -y
sudo apt install -y terraform

sudo apt update
sudo apt install etcd-client

echo "==> Verifying installations..."
echo "--------------------------------------"
echo "Git:"
git --version
echo "--------------------------------------"
echo "Zsh:"
zsh --version
echo "--------------------------------------"
echo "Docker:"
docker --version
echo "--------------------------------------"
echo "Kubectl:"
kubectl version --client
echo "--------------------------------------"
echo "Helm:"
helm version
echo "--------------------------------------"
echo "Minikube:"
minikube version
echo "--------------------------------------"
echo "Kubecolor:"
kubecolor version
echo "--------------------------------------"
echo "Ansible:"
ansible --version
echo "--------------------------------------"
echo "Terraform:"
terraform --version
echo "--------------------------------------"
echo "etcdctl:"
etcdctl version
echo "--------------------------------------"

echo "==> DONE"
echo "⚠️ IMPORTANT: run 'newgrp docker' OR reboot"
echo "👉 Then run: zsh && p10k configure"

# configure p10k right prompt elements if .p10k.zsh exists
echo "Update $HOME/.p10k.zsh with following value"
echo "typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=("
echo "  memory_usage" 
echo "  disk_usage"
echo "  load"
echo ")"

sudo timedatectl set-timezone Asia/Ho_Chi_Minh
p10k configure
