#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Laravel Auto Installer (Optimized Version)
# Includes: Optional MySQL, Optional phpMyAdmin, SSL, Nginx
# With: Input validation, logging, error handling & rollback
# =========================================================

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ---------- Logging ----------
LOG_FILE="/var/log/laravel-installer.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- Helpers ----------
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

rollback() {
  warn "Rollback executed."

  [[ -n "${PROJECT_DIR:-}" ]] && rm -rf "$PROJECT_DIR" || true
  rm -f "/etc/nginx/sites-enabled/${PROJECT_NAME}.conf" || true
  rm -f "/etc/nginx/sites-available/${PROJECT_NAME}.conf" || true

  warn "Rollback completed."
}
trap rollback ERR

# ---------- OS ----------
detect_os() {
  DISTRO=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  RELEASE=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"')
  log "Detected OS: $DISTRO $RELEASE"
}

# ---------- PHP ----------
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
  validate_not_empty "$PHP_VERSION"
}

install_php_stack() {
  local pkgs=(php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath nginx git unzip)
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  systemctl enable php${PHP_VERSION}-fpm nginx
}

# ---------- Composer ----------
install_composer() {
  if ! command -v composer >/dev/null; then
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
  fi
}

# ---------- MySQL ----------
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

# ---------- Project ----------
clone_project() {
  PROJECT_DIR="/var/www/${PROJECT_NAME}"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  git clone -b "$GIT_BRANCH" "$GIT_REPO" . || {
    log "Branch not found. Cloning default branch..."
    git clone "$GIT_REPO" .
  }

  if ! composer install --no-interaction --prefer-dist; then
    err "Composer installation failed."
    exit 1
  fi

  cp .env.example .env || true
}

create_new_laravel() {
  PROJECT_DIR="/var/www/${PROJECT_NAME}"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  composer create-project laravel/laravel . --no-interaction
}

configure_env() {
  cd "$PROJECT_DIR"

  sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN_NAME}|" .env
  sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=mysql|" .env
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
  sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

  php artisan key:generate
  php artisan config:cache
}

run_migrations() {
  php artisan migrate --force || warn "Migration warning."
}

run_seeders() {
  php artisan db:seed --force || warn "Seeder warning."
}

# ---------- Nginx ----------
create_nginx_conf() {
  NGINX_FILE="/etc/nginx/sites-available/${PROJECT_NAME}.conf"
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

  if ! nginx -t; then
    err "Nginx config invalid."
    exit 1
  fi

  systemctl reload nginx
}

# ---------- Permissions ----------
fix_permissions() {
  chown -R www-data:www-data "$PROJECT_DIR"

  find "$PROJECT_DIR/storage" -type d -exec chmod 755 {} \;
  find "$PROJECT_DIR/storage" -type f -exec chmod 644 {} \;

  find "$PROJECT_DIR/bootstrap/cache" -type d -exec chmod 755 {} \;
  find "$PROJECT_DIR/bootstrap/cache" -type f -exec chmod 644 {} \;
}

# ---------- SSL ----------
install_ssl() {
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect || true
}

# ---------- phpMyAdmin ----------
install_phpmyadmin() {
  apt-get install -y php${PHP_VERSION}-mysql phpmyadmin

  ln -sf /usr/share/phpmyadmin /var/www/phpmyadmin

  PMA_DOMAIN=$(ask "phpMyAdmin domain" "pma.${DOMAIN_NAME}")

  cat >/etc/nginx/sites-available/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name $PMA_DOMAIN;
    root /var/www/phpmyadmin;

    index index.php index.html;

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$PMA_DOMAIN" --non-interactive --agree-tos -m "admin@${PMA_DOMAIN}" --redirect || true
}

# =========================================================
# MAIN
# =========================================================
main() {
  require_root
  detect_os
  add_php_repo
  select_php
  install_php_stack
  install_composer

  INSTALL_METHOD=$(ask "1) New Laravel  2) Git repo" "1")

  PROJECT_NAME=$(ask "Project folder name" "laravel-app")
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
  fix_permissions
  install_ssl

  INSTALL_PMA=$(ask "Install phpMyAdmin? (y/n)" "n")
  [[ "$INSTALL_PMA" =~ ^[Yy]$ ]] && install_phpmyadmin

  log "Laravel installation completed."
  echo -e "${GREEN}URL: https://${DOMAIN_NAME}${NC}"
}

main "$@"
