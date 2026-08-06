#!/usr/bin/env bash
# =============================================================================
# LogOps — Setup script for Amazon Linux 2023 EC2
# Run as: sudo bash scripts/setup-aws-linux.sh
# Installs Docker, Compose plugin, Git, and prepares log directories.
# =============================================================================

set -euo pipefail

log() {
  # Print a timestamped status line so beginners can follow progress
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

require_root() {
  # Ensure we can install packages and change sysctl settings
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root: sudo bash $0" >&2
    exit 1
  fi
}

update_packages() {
  # Refresh package metadata and apply security updates
  log "Updating system packages..."
  dnf update -y
}

install_base_tools() {
  # Install utilities needed by LogOps setup and health checks
  log "Installing base packages..."
  dnf install -y git curl wget unzip tar jq amazon-ssm-agent
  systemctl enable --now amazon-ssm-agent || true
}

install_docker() {
  # Install Docker Engine and enable it on boot
  log "Installing Docker..."
  dnf install -y docker
  systemctl enable --now docker
  # Allow the default EC2 user to run docker without sudo
  usermod -aG docker ec2-user || true
}

install_compose_plugin() {
  # Install Docker Compose V2 plugin if missing
  log "Installing Docker Compose plugin..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  if ! docker compose version >/dev/null 2>&1; then
    COMPOSE_VERSION="v2.24.5"
    curl -fsSL \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi
  docker compose version
}

prepare_logops_dirs() {
  # Create folders for app logs and the project checkout
  log "Creating LogOps directories..."
  mkdir -p /var/log/logops /opt/logops
  chown -R ec2-user:ec2-user /var/log/logops /opt/logops
  chmod 755 /var/log/logops /opt/logops
}

tune_sysctl() {
  # Raise file descriptor / map limits for ClickHouse and Kafka clients
  log "Applying sysctl tuning..."
  cat >/etc/sysctl.d/99-logops.conf <<'EOF'
fs.file-max = 2097152
vm.max_map_count = 262144
net.core.somaxconn = 4096
net.ipv4.ip_local_port_range = 1024 65535
EOF
  sysctl --system
}

raise_ulimits() {
  # Persist higher nofile limits for interactive and service users
  log "Raising ulimits..."
  cat >/etc/security/limits.d/99-logops.conf <<'EOF'
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144
EOF
}

main() {
  require_root
  update_packages
  install_base_tools
  install_docker
  install_compose_plugin
  prepare_logops_dirs
  tune_sysctl
  raise_ulimits
  log "Setup complete. Log out/in (or reboot) so the docker group applies to ec2-user."
  log "Next: copy the LogOps project to /opt/logops and run docker compose up -d"
}

main "$@"
