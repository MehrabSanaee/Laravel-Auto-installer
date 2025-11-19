#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Laravel Auto Installer – Improved Version
# Focus: Safe VPS installation for Laravel Telegram Bot
# =========================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

LOG_FILE="/var/log/laravel-installer.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

# --------------------------- Helpers ---------------------------

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Run as root."
    exit 1
  fi
}

ask() {
  local prompt="$1" default="$2" input
  read -p "$prompt [$default]: " input
  echo "${input:-$default}"
}

validate_not_empty() {
  if [[ -z "$1" ]]; then
    err "Invalid empty input."
    exit 1
  fi
}

# --------------------------- Rollback ---------------------------

rollback() {
  warn "Rollback triggered…"

  # Restore nginx config backup
  if [[ -f "/etc/nginx/sites-available/${PROJECT_NAME}.conf.bak" ]]; then
    mv "/etc/nginx/sites-available/${PROJECT_NAME}.conf.bak" \
       "/etc/nginx/sites-available/${PROJECT_NAME}.conf"
    systemctl reload nginx || true
  fi

  # Remove project directory
  if [[ -n "${PROJECT_DIR:-}" && -d "$PROJECT_DIR" ]]; then
    rm -rf "$PROJECT_DIR"
  fi

  warn "Rollback completed (limited)."
}
trap rollback ERR

# --------------------------- OS Detect ---------------------------

detect_os() {
  DISTRO=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  RELEASE=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"')
  log "Detected OS: $DISTRO $RELEASE"
}

# --------------------------- Internet Check ---------------------------

check_internet() {
  if ! ping -c1 8.8.8.8 >/dev/null 2>&1; then
    err "No internet detected."
    exit 1
  fi
}

# --------------------------- PHP & Composer ---------------------------

add_php_repo() {
  apt-get update -y
  apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https curl gnupg
  add-apt-repository -y ppa:ondrej/php
  apt-get update -y
}

select_php() {
  local versions=("8.3" "8.2" "8.1" "8.0")
  echo "Available PHP versions:"
  for i in "${!versions[@]}"; do echo "$((i+1))) PHP ${versions[$i]}"; done

  read -p "Select PHP version [1]: " idx
  idx="${idx:-1}"
  PHP_VERSION="${versions[$((idx-1))]}"
}

install_php_stack() {
  local pkgs=(php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-mysql nginx git unzip)
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  systemctl enable php${PHP_VERSION}-fpm nginx

  if [[ ! -S "/var/run/php/php${PHP_VERSION}-fpm.sock" ]]; then
    err "PHP-FPM socket missing. PHP installation failed."
    exit 1
  fi
}

install_composer() {
  if ! command -v composer >/dev/null; then
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
  fi
}

# --------------------------- MySQL ---------------------------

install_mysql() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
  systemctl enable mysql
}

create_db() {
  mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
}

# --------------------------- Project ---------------------------

safe_update_env() {
  local key=$1
  local value=$2

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

clone_project() {
  PROJECT_DIR="/var/www/${PROJECT_NAME}"

  if [[ -d "$PROJECT_DIR" && "$(ls -A $PROJECT_DIR)" ]]; then
    err "Project directory exists and is not empty: $PROJECT_DIR"
    exit 1
  fi

  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  if ! git clone -b "$GIT_BRANCH" "$GIT_REPO" .; then
    err "Git clone failed."
    exit 1
  fi

  if ! composer install --no-interaction --prefer-dist; then
    err "Composer install failed."
    exit 1
  fi

  cp .env.example .env 2>/dev/null || true
}

create_new_laravel() {
  PROJECT_DIR="/var/www/${PROJECT_NAME}"

  if [[ -d "$PROJECT_DIR" && "$(ls -A $PROJECT_DIR)" ]]; then
    err "Project directory exists and is not empty: $PROJECT_DIR"
    exit 1
  fi

  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  composer create-project laravel/laravel . --no-interaction
}

configure_env() {
  cd "$PROJECT_DIR"

  safe_update_env "APP_URL" "https://${DOMAIN_NAME}"
  safe_update_env "DB_CONNECTION" "mysql"
  safe_update_env "DB_DATABASE" "${DB_NAME}"
  safe_update_env "DB_USERNAME" "${DB_USER}"
  safe_update_env "DB_PASSWORD" "${DB_PASS}"

  php artisan key:generate
  php artisan config:cache
}

run_migrations() {
  if ! php artisan migrate --force; then
    err "Migration failed."
    exit 1
  fi
}

run_seeders() {
  php artisan db:seed --force || warn "Seeder warning."
}

# --------------------------- Nginx ---------------------------

create_nginx_conf() {
  NGINX_FILE="/etc/nginx/sites-available/${PROJECT_NAME}.conf"

  if [[ -f "$NGINX_FILE" ]]; then
    err "Nginx config already exists: $NGINX_FILE"
    exit 1
  fi

  cat >"$NGINX_FILE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    root /var/www/${PROJECT_NAME}/public;

    index index.php index.html;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF

  ln -sf "$NGINX_FILE" /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
}

# --------------------------- SSL ---------------------------

install_ssl() {
  SERVER_IP=$(curl -s ifconfig.me)
  DNS_IP=$(dig +short $DOMAIN_NAME | tail -n1)

  if [[ "$DNS_IP" != "$SERVER_IP" ]]; then
    warn "DNS does not point here. Skipping SSL."
    return
  fi

  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect || true
}

# --------------------------- PMA ---------------------------

install_phpmyadmin() {
  warn "phpMyAdmin from apt is insecure. Use only for testing."
  sleep 1
}

# =========================================================
# MAIN
# =========================================================

main() {
  require_root
  detect_os
  check_internet
  add_php_repo
  select_php
  install_php_stack
  install_composer

  INSTALL_METHOD=$(ask "1) New Laravel  2) Git repo" "1")

  PROJECT_NAME=$(ask "Project folder name" "laravel-bot")
  validate_not_empty "$PROJECT_NAME"

  DOMAIN_NAME=$(ask "Domain name" "example.com")
  validate_not_empty "$DOMAIN_NAME"

  USE_DB=$(ask "Use MySQL database? (y/n)" "y")

  if [[ "$USE_DB" =~ ^[Yy]$ ]]; then
    install_mysql
    DB_NAME=$(ask "DB name" "laravel_db")
    DB_USER=$(ask "DB user" "laravel_user")
    DB_PASS=$(ask "DB password" "ChangeMe123!")
    create_db
  fi

  if [[ "$INSTALL_METHOD" == "1" ]]; then
    create_new_laravel
  else
    GIT_REPO=$(ask "Git repository URL" "")
    validate_not_empty "$GIT_REPO"

    GIT_BRANCH=$(ask "Git branch" "main")
    clone_project
  fi

  configure_env
  run_migrations
  run_seeders
  create_nginx_conf
  install_ssl

  INSTALL_PMA=$(ask "Install phpMyAdmin? (y/n)" "n")
  [[ "$INSTALL_PMA" =~ ^[Yy]$ ]] && install_phpmyadmin

  log "Laravel installation completed."
  echo -e "${GREEN}URL: https://${DOMAIN_NAME}${NC}"
}

main "$@"
