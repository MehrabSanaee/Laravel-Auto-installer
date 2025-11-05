#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Laravel Auto Installer (Full Root Version)
# Includes: Laravel, PHP, Nginx, MySQL, Composer, SSL, phpMyAdmin
# Compatible: Ubuntu 20.04 / 22.04
# ---------------------------------------------------------

# ========== COLORS ==========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ========== HELPERS ==========
log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    warn "Script needs root. Re-running with sudo..."
    exec sudo "$0" "$@"
  fi
}

ask() {
  local prompt="$1" default="$2" input
  read -p "$prompt [$default]: " input
  echo "${input:-$default}"
}

# ========== OS DETECTION ==========
detect_os() {
  DISTRO=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  RELEASE=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"')
  log "Detected OS: ${DISTRO} ${RELEASE}"
}

# ========== PHP + COMPOSER + NGINX + MYSQL ==========
add_php_repo() {
  apt-get update -y
  apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https curl gnupg
  add-apt-repository -y ppa:ondrej/php || true
  apt-get update -y
}

select_php_version() {
  local versions=("8.3" "8.2" "8.1" "8.0" "7.4")
  echo -e "${BLUE}Available PHP versions:${BLUE}"
  for i in "${!versions[@]}"; do echo "$((i+1))) PHP ${versions[$i]}"; done
  read -p "Select PHP version [1]: " idx
  idx="${idx:-1}"
  PHP_VERSION="${versions[$((idx-1))]}"
  log "Selected PHP $PHP_VERSION"
}

install_php_stack() {
  local pkgs=(php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mysql php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath nginx mysql-server git unzip expect)
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  systemctl enable php${PHP_VERSION}-fpm nginx mysql
  systemctl restart php${PHP_VERSION}-fpm nginx mysql
}

install_composer() {
  if ! command -v composer &>/dev/null; then
    log "Installing Composer..."
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
  fi
  log "$(composer --version)"
}

# ========== DATABASE ==========
create_database() {
  if [[ "${NEED_DB:-y}" =~ ^[Yy]$ ]]; then
    mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
  fi
}

# ========== PROJECT ==========
clone_project() {
  PROJECT_DIR="/var/www/${PROJECT_NAME}"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"
  if [[ -n "${GIT_BRANCH:-}" ]]; then
    git clone -b "${GIT_BRANCH}" "${GIT_REPO}" . || git clone "${GIT_REPO}" .
  else
    git clone "${GIT_REPO}" .
  fi
  composer install --no-interaction --prefer-dist || true
  [ -f ".env.example" ] && cp .env.example .env
}

configure_env() {
  cd "$PROJECT_DIR"
  sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN_NAME}|" .env || echo "APP_URL=https://${DOMAIN_NAME}" >> .env
  sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=mysql|" .env || echo "DB_CONNECTION=mysql" >> .env
  sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|" .env || echo "DB_HOST=127.0.0.1" >> .env
  sed -i "s|DB_PORT=.*|DB_PORT=3306|" .env || echo "DB_PORT=3306" >> .env
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env || echo "DB_DATABASE=${DB_NAME}" >> .env
  sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env || echo "DB_USERNAME=${DB_USER}" >> .env
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env || echo "DB_PASSWORD=${DB_PASS}" >> .env

  php artisan key:generate || true
  php artisan config:cache || true
}

run_laravel_migrate() {
  cd "$PROJECT_DIR"
  log "Running Laravel migrations..."
  php artisan migrate --force || warn "Migration failed — check DB connection or permissions."
}

# ========== NGINX ==========
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

    location ~ /\.ht {
        deny all;
    }
}
EOF
  ln -sf "$NGINX_FILE" /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default || true
  nginx -t && systemctl reload nginx
}

# ========== PERMISSIONS ==========
fix_permissions() {
  log "Fixing permissions..."
  chown -R www-data:www-data "$PROJECT_DIR"
  chmod -R 775 "$PROJECT_DIR/storage" "$PROJECT_DIR/bootstrap/cache"
}

# ========== SSL ==========
install_ssl() {
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect || true
}

# ========== PHPMYADMIN ==========
install_phpmyadmin() {
  PHPMYADMIN_DOMAIN=$(ask "phpMyAdmin domain (e.g. pma.example.com)" "pma.${DOMAIN_NAME}")
  PHPMYADMIN_PASS=$(ask "phpMyAdmin MySQL password" "${DB_PASS}")

  DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin

  ln -s /usr/share/phpmyadmin /var/www/phpmyadmin || true

  cat >/etc/nginx/sites-available/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name ${PHPMYADMIN_DOMAIN};
    root /var/www/phpmyadmin;

    index index.php index.html;
    location / {
        index index.php index.html;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$PHPMYADMIN_DOMAIN" --non-interactive --agree-tos -m "admin@${PHPMYADMIN_DOMAIN}" --redirect || true
  log "phpMyAdmin available at: https://${PHPMYADMIN_DOMAIN}"
}

# ========== MAIN ==========
main() {
  require_root
  detect_os
  add_php_repo
  select_php_version
  install_php_stack
  install_composer

  echo -e "${YELLOW}Choose installation method:${NC}"
  echo "1) Fresh Laravel installation"
  echo "2) Use GitHub repository"
  read -p "Select [1]: " INSTALL_METHOD
  INSTALL_METHOD="${INSTALL_METHOD:-1}"

  PROJECT_NAME=$(ask "Project folder name" "laravel-app")
  DOMAIN_NAME=$(ask "Domain name" "example.com")
  NEED_DB=$(ask "Does project use a database? (y/n)" "y")
  DB_NAME=$(ask "Database name" "laravel_db")
  DB_USER=$(ask "Database user" "laravel_user")
  DB_PASS=$(ask "Database password" "ChangeMe123!")

  create_database

  if [[ "$INSTALL_METHOD" == "1" ]]; then
    PROJECT_DIR="/var/www/${PROJECT_NAME}"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    log "Creating new Laravel project..."
    composer create-project laravel/laravel . || true
  else
    GIT_REPO=$(ask "Git repository URL" "")
    GIT_BRANCH=$(ask "Git branch" "main")
    clone_project
  fi

  configure_env
  run_laravel_migrate
  create_nginx_conf
  fix_permissions
  install_ssl
  install_phpmyadmin

  log "✅ Laravel installation complete."
  echo -e "${GREEN}Visit: https://${DOMAIN_NAME}${NC}"
}

main "$@"
