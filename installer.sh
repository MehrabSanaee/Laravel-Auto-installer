#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Secure Laravel Installer + phpMyAdmin (Basic Auth Mandatory)
# =========================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

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

validate_domain() {
  if [[ ! "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    err "Invalid domain name: $1"
    exit 1
  fi
}

validate_ip() {
  if [[ ! "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    err "Invalid IP address: $1"
    exit 1
  fi
}

validate_password() {
  if [[ ${#1} -lt 8 ]]; then
    err "Password must be at least 8 characters"
    exit 1
  fi
}

# --------------------------- Rollback ---------------------------

rollback() {
  warn "Rollback triggered…"

  if [[ -f "/etc/nginx/sites-available/${PROJECT_NAME}.conf.bak" ]]; then
    mv "/etc/nginx/sites-available/${PROJECT_NAME}.conf.bak" \
       "/etc/nginx/sites-available/${PROJECT_NAME}.conf"
    systemctl reload nginx || true
  fi

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
  apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https curl gnupg dirmngr
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
  local pkgs=(php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-mysql nginx git unzip wget gnupg2)
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
  mkdir -p /etc/nginx/snippets
  touch /etc/nginx/snippets/phpmyadmin.conf

  local NGINX_FILE="/etc/nginx/sites-available/${PROJECT_NAME}.conf"

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

    include /etc/nginx/snippets/phpmyadmin.conf;
}
EOF

  ln -sf "$NGINX_FILE" /etc/nginx/sites-enabled/
  if ! nginx -t; then
    err "Nginx configuration test failed - check syntax"
    exit 1
  fi
  systemctl reload nginx
}

# --------------------------- SSL ---------------------------

install_ssl() {
  SERVER_IP=$(curl -s ifconfig.me)
  DNS_IP=$(dig +short $DOMAIN_NAME | tail -n1)

  if [[ -z "$DNS_IP" || "$DNS_IP" != "$SERVER_IP" ]]; then
    warn "DNS does not point here or cannot be resolved. Skipping SSL."
    return
  fi

  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect || true
}

# --------------------------- Secure phpMyAdmin ---------------------------

install_phpmyadmin_secure() {
  local alias_path="/${PMA_ALIAS}"
  local install_dir="/usr/share/phpmyadmin"

  apt-get update -y
  apt-get install -y wget unzip apache2-utils php${PHP_VERSION}-mbstring php${PHP_VERSION}-mysqli

  log "Downloading phpMyAdmin upstream package (latest)..."
  cd /tmp
  wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz -O phpmyadmin.tar.gz
  tar xzf phpmyadmin.tar.gz
  rm -rf "$install_dir" || true
  mv phpMyAdmin-*-all-languages "$install_dir"
  rm -f phpmyadmin.tar.gz

  mkdir -p "$install_dir/tmp"
  chown www-data:www-data "$install_dir/tmp"
  chmod 770 "$install_dir/tmp"

  BLOWFISH=$(openssl rand -base64 32)
  cat > "$install_dir/config.inc.php" <<EOF
<?php
\$cfg['blowfish_secret'] = '${BLOWFISH}';
\$cfg['TempDir'] = '/usr/share/phpmyadmin/tmp';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
EOF

  SNIPPET_FILE="/etc/nginx/snippets/phpmyadmin.conf"
  cat > "$SNIPPET_FILE" <<EOF
# phpMyAdmin snippet - alias: ${alias_path}
location ${alias_path} {
    index index.php index.html index.htm;
    root /usr/share/phpmyadmin;
    try_files \$uri \$uri/ =404;
}

location ~ ^${alias_path}/.+\.php\$ {
    root /usr/share/phpmyadmin;
    include snippets/fastcgi-php.conf;
    fastcgi_param SCRIPT_FILENAME /usr/share/phpmyadmin\$fastcgi_script_name;
    fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
}

# Basic auth (mandatory)
auth_basic "Restricted";
auth_basic_user_file /etc/nginx/.pma_pass;
EOF

  htpasswd -b -c /etc/nginx/.pma_pass "${PMA_USER}" "${PMA_PASS}"

  if [[ -n "${PMA_ALLOW_IP}" ]]; then
    validate_ip "$PMA_ALLOW_IP"
    cat >> "$SNIPPET_FILE" <<EOF
# Allow specific IP only
allow ${PMA_ALLOW_IP};
deny all;
EOF
  fi

  nginx -t && systemctl reload nginx
  log "phpMyAdmin installed at: ${alias_path} (mapped to /usr/share/phpmyadmin)"
  log "Basic auth enabled for phpMyAdmin user: ${PMA_USER}"
}

# --------------------------- MAIN ---------------------------

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
  validate_domain "$DOMAIN_NAME"

  USE_DB=$(ask "Use MySQL database? (y/n)" "y")
  if [[ "$USE_DB" =~ ^[Yy]$ ]]; then
    install_mysql
    DB_NAME=$(ask "DB name" "laravel_db")
    DB_USER=$(ask "DB user" "laravel_user")
    DB_PASS=$(ask "DB password" "ChangeMe123!")
    validate_password "$DB_PASS"
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

  PMA_INSTALL=$(ask "Install phpMyAdmin? (y/n)" "y")
  if [[ "$PMA_INSTALL" =~ ^[Yy]$ ]]; then
    PMA_ALIAS=$(ask "phpMyAdmin alias (no trailing slash)" "pma")
    validate_not_empty "$PMA_ALIAS"
    PMA_USER=$(ask "Basic-auth username for phpMyAdmin" "pmaadmin")
    validate_not_empty "$PMA_USER"
    PMA_PASS=$(ask "Basic-auth password for phpMyAdmin" "RandomPass$(date +%s)")
    validate_password "$PMA_PASS"
    PMA_ALLOW_IP=$(ask "Restrict phpMyAdmin access to single IP? (leave empty for all)" "")
  fi

  configure_env
  run_migrations
  run_seeders
  create_nginx_conf
  install_ssl

  if [[ "$PMA_INSTALL" =~ ^[Yy]$ ]]; then
    install_phpmyadmin_secure
  fi

  log "Laravel installation completed."
  echo -e "${GREEN}URL: https://${DOMAIN_NAME}${NC}"
  if [[ "$PMA_INSTALL" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}phpMyAdmin URL: https://${DOMAIN_NAME}/${PMA_ALIAS}${NC}"
    echo -e "${YELLOW}phpMyAdmin basic-auth username: ${PMA_USER}${NC}"
  fi
}

main "$@"
