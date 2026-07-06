#!/usr/bin/env bash
set -uo pipefail

# Disable interactive frontend prompts and restart services automatically
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# -----------------------------
# CONFIGURATION: Select Packages to Install
# -----------------------------
# Add or remove packages from this array to control what gets installed.
INSTALL_PACKAGES=(
  "zsh"
  "docker"
  "kubectl"
  "kubecolor"
  "helm"
  "kubectx"
  "minikube"
  "ansible"
  "terraform"
  "etcd-client"
  "webmin"
)

# Helper function to check if a package is selected for installation
is_enabled() {
  local target="$1"
  local item
  for item in "${INSTALL_PACKAGES[@]}"; do
    [[ "$item" == "$target" ]] && return 0
  done
  return 1
}

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
  git curl wget apt-transport-https ca-certificates gnupg lsb-release \
  vim fonts-powerline

# -----------------------------
# DOCKER INSTALL
# -----------------------------
if is_enabled "docker"; then
  echo "==> Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo usermod -aG docker $USER || true
fi

# -----------------------------
# KUBECTL
# -----------------------------
if is_enabled "kubectl"; then
  echo "==> Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

# -----------------------------
# KUBECOLOR
# -----------------------------
if is_enabled "kubecolor"; then
  echo "==> Installing kubecolor..."
  wget https://github.com/kubecolor/kubecolor/releases/download/v0.6.0/kubecolor_0.6.0_linux_amd64.tar.gz
  tar -xvzf kubecolor_0.6.0_linux_amd64.tar.gz kubecolor
  sudo mv kubecolor /usr/local/bin/
  sudo chmod +x /usr/local/bin/kubecolor
  rm -f kubecolor_0.6.0_linux_amd64.tar.gz
fi

# -----------------------------
# HELM
# -----------------------------
if is_enabled "helm"; then
  echo "==> Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -----------------------------
# KUBECTX / KUBENS
# -----------------------------
if is_enabled "kubectx"; then
  echo "==> Installing kubectx & kubens..."
  sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx

  sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
  sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
fi

# -----------------------------
# MINIKUBE
# -----------------------------
if is_enabled "minikube"; then
  echo "==> Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64
  sudo mv minikube-linux-amd64 /usr/local/bin/minikube
  minikube addons enable metrics-server
fi

# -----------------------------
# ZSH INSTALLATION & CONFIG
# -----------------------------
if is_enabled "zsh"; then
  echo "==> Installing Zsh..."
  sudo apt install -y zsh

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

  grep -q "alias.verbose" "$ZSHRC" || \
  echo 'source /usr/share/alias.verbose' >> "$ZSHRC"

  grep -q "kubectl completion zsh" "$ZSHRC" || cat <<'EOF' >> "$ZSHRC"

# --- kubectl autocomplete ---
autoload -Uz compinit
compinit
source <(kubectl completion zsh)
alias k=kubectl
compdef _kubectl k
EOF

  echo 'plugins=(git zsh-autosuggestions zsh-autocomplete)' >> "$ZSHRC"
  echo 'source ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$ZSHRC"
  echo 'source ~/.oh-my-zsh/custom/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh' >> "$ZSHRC"
  echo 'source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme' >> "$ZSHRC"
  echo 'typeset -g POWERLEVEL9K_INSTANT_PROMPT=off' >> "$ZSHRC"
fi

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
if is_enabled "ansible"; then
  echo "==> Installing Ansible..."
  sudo add-apt-repository --yes --update ppa:ansible/ansible
  sudo apt install -y ansible
fi

# -----------------------------
# TERRAFORM
# -----------------------------
if is_enabled "terraform"; then
  echo "==> Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo \
  "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

  sudo apt update -y
  sudo apt install -y terraform
fi

# -----------------------------
# ETCD-CLIENT
# -----------------------------
if is_enabled "etcd-client"; then
  echo "==> Installing etcd-client..."
  sudo apt install -y etcd-client
fi

# -----------------------------
# WEBMIN
# -----------------------------
if is_enabled "webmin"; then
  echo "==> Installing Webmin..."
  # Download and install the Webmin repository setup script cleanly
  wget https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
  # Run the setup script with 'force' (-f) to overwrite the repository configurations
  sudo sh webmin-setup-repo.sh -f
  # Explicitly update your system's package list index 🌟
  sudo apt update -y
  # Re-run the installation
  sudo apt install -y webmin
  # Clean up setup script
  rm -f webmin-setup-repo.sh
fi

echo "==> Verifying installations..."
echo "--------------------------------------"
echo "Git:"
git --version
echo "--------------------------------------"

if is_enabled "zsh"; then
  echo "Zsh:"
  zsh --version
  echo "--------------------------------------"
fi

if is_enabled "docker"; then
  echo "Docker:"
  docker --version
  echo "--------------------------------------"
fi

if is_enabled "kubectl"; then
  echo "Kubectl:"
  kubectl version --client
  echo "--------------------------------------"
fi

if is_enabled "helm"; then
  echo "Helm:"
  helm version
  echo "--------------------------------------"
fi

if is_enabled "minikube"; then
  echo "Minikube:"
  minikube version
  echo "--------------------------------------"
fi

if is_enabled "kubecolor"; then
  echo "Kubecolor:"
  kubecolor version
  echo "--------------------------------------"
fi

if is_enabled "ansible"; then
  echo "Ansible:"
  ansible --version
  echo "--------------------------------------"
fi

if is_enabled "terraform"; then
  echo "Terraform:"
  terraform --version
  echo "--------------------------------------"
fi

if is_enabled "etcd-client"; then
  echo "etcdctl:"
  etcdctl version
  echo "--------------------------------------"
fi

if is_enabled "webmin"; then
  echo "Webmin:"
  dpkg -s webmin | grep Version || echo "Not installed"
  echo "go to web in https://$(hostname -I | awk '{print $1}'):10000"
  echo "--------------------------------------"
fi

echo "==> DONE"

if is_enabled "zsh"; then
  echo "⚠️ IMPORTANT: run 'exec zsh'"
  echo "👉 Then run: zsh && p10k configure"
fi

sudo timedatectl set-timezone Asia/Ho_Chi_Minh

if is_enabled "zsh"; then
  sudo chsh -s $(which zsh) $USER
  exec zsh
  p10k configure
fi
#autoload -Uz zsh-newuser-install && zsh-newuser-install -f
