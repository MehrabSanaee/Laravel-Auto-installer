#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Laravel Git Installer (No user restrictions)
# Ubuntu 20.04 / 22.04 — Nginx, PHP, MySQL, Composer, Certbot
# Based on original installer.sh
# ---------------------------------------------------------

# ========== COLORS ==========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ========== LOGO ==========
show_logo() {
  echo -e "${BLUE}"
  cat <<'EOF'
                _         __          __  _        _____
     /\        | |        \ \        / / | |      / ____|
    /  \  _   _| |_ ___    \ \  /\  / /__| |__   | (___   ___ _ ____   _____ _ __
   / /\ \| | | | __/ _ \    \ \/  \/ / _ \ '_ \   \___ \ / _ \ '__\ \ / / _ \ '__|
  / ____ \ |_| | || (_) |    \  /\  /  __/ |_) |  ____) |  __/ |   \ V /  __/ |
 /_/    \_\__,_|\__\___/      \/  \/ \___|_.__/  |_____/ \___|_|    \_/ \___|_|
  Laravel Project Auto Installer (root mode)
EOF
  echo -e "${NC}"
}

# ========== HELPERS ==========
log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }

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
  if command -v lsb_release &>/dev/null; then
    DISTRO="$(lsb_release -is)"
    RELEASE="$(lsb_release -rs)"
  else
    DISTRO=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
    RELEASE=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"')
  fi
  log "Detected: ${DISTRO} ${RELEASE}"
}

# ========== PHP ==========
add_php_repo() {
  apt-get update -y
  apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https curl gnupg
  add-apt-repository -y ppa:ondrej/php || true
  apt-get update -y
}

select_php_version() {
  local versions=("8.3" "8.2" "8.1" "8.0")
  echo -e "${BLUE}Available PHP versions:${NC}"
  for i in "${!versions[@]}"; do echo "$((i+1))) PHP ${versions[$i]}"; done
  read -p "Select PHP version [1]: " idx
  idx="${idx:-1}"
  PHP_VERSION="${versions[$((idx-1))]}"
  log "Selected PHP $PHP_VERSION"
}

install_php() {
  local pkgs=(php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath)
  apt-get install -y "${pkgs[@]}"
  systemctl enable php${PHP_VERSION}-fpm && systemctl restart php${PHP_VERSION}-fpm
}

# ========== COMPOSER ==========
install_composer() {
  if ! command -v composer &>/dev/null; then
    log "Installing Composer..."
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php
  fi
  log "$(composer --version)"
}

# ========== NGINX + MYSQL ==========
install_nginx_mysql() {
  apt-get install -y nginx mysql-server git
  systemctl enable nginx mysql
  systemctl start nginx mysql
}

# ========== DATABASE ==========
create_database() {
  if [[ "${NEED_DB:-n}" =~ ^[Yy]$ ]]; then
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
  # Support both branch and default clone; run as root (no sudo -u)
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
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env || echo "DB_DATABASE=${DB_NAME}" >> .env
  sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env || echo "DB_USERNAME=${DB_USER}" >> .env
  sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env || echo "DB_PASSWORD=${DB_PASS}" >> .env
  # run artisan commands as root (or you can switch to www-data if preferred)
  php artisan key:generate || true
  php artisan config:cache || true
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
set_permissions() {
  # Make web files owned by www-data (webserver) and group www-data
  chown -R www-data:www-data "$PROJECT_DIR"
  chmod -R 775 "$PROJECT_DIR/storage" "$PROJECT_DIR/bootstrap/cache" || true
}

# ========== SSL ==========
install_ssl() {
  log "Installing Certbot for SSL..."
  apt-get install -y certbot python3-certbot-nginx
  if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect; then
    log "SSL successfully installed for https://${DOMAIN_NAME}"
  else
    warn "SSL setup failed. Check DNS or open ports 80/443."
  fi
}

# ========== PHPMYADMIN Install ==========
install_phpmyadmin() {
  log "Installing phpMyAdmin..."
  apt-get install -y phpmyadmin php${PHP_VERSION}-mbstring php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-xml php${PHP_VERSION}-curl

  PHPMYADMIN_DIR="/usr/share/phpmyadmin"
  if [[ ! -d "$PHPMYADMIN_DIR" ]]; then
    log "phpMyAdmin directory not found, creating symlink..."
    ln -s /usr/share/phpmyadmin /var/www/phpmyadmin
    PHPMYADMIN_DIR="/var/www/phpmyadmin"
  fi

  # تنظیم دامنه phpMyAdmin
  NGINX_PHPMYADMIN="/etc/nginx/sites-available/phpmyadmin.conf"
  cat > "$NGINX_PHPMYADMIN" <<EOF
server {
    listen 80;
    server_name ${PHPMYADMIN_DOMAIN};
    root ${PHPMYADMIN_DIR};

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

    auth_basic "Restricted Area";
    auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;
}
EOF

  # ایجاد فایل رمز برای ورود
  log "Creating phpMyAdmin login credentials..."
  apt-get install -y apache2-utils >/dev/null 2>&1
  htpasswd -b -c /etc/nginx/.phpmyadmin_htpasswd "${PHPMYADMIN_USER}" "${PHPMYADMIN_PASS}"

  ln -sf "$NGINX_PHPMYADMIN" /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx

  # SSL خودکار برای دامنه phpMyAdmin
  if [[ "$PHPMYADMIN_DOMAIN" != "localhost" ]]; then
    log "Obtaining SSL for phpMyAdmin domain..."
    certbot --nginx -d "$PHPMYADMIN_DOMAIN" --non-interactive --agree-tos -m "admin@${PHPMYADMIN_DOMAIN}" --redirect || warn "SSL setup failed for phpMyAdmin."
  fi

  log "✅ phpMyAdmin installed and accessible at: https://${PHPMYADMIN_DOMAIN}"
}

# ========== MAIN ==========
main() {
  show_logo
  require_root
  detect_os
  add_php_repo
  select_php_version

  # No user selection — run everything as root, later files owned by www-data
  USER_NAME="root"

  echo -e "\n${YELLOW}Choose installation method:${NC}"
  echo "1) Fresh Laravel installation"
  echo "2) Use GitHub repository"
  read -p "Select an option [1]: " INSTALL_METHOD
  INSTALL_METHOD="${INSTALL_METHOD:-1}"

  if [[ "$INSTALL_METHOD" == "1" ]]; then
    PROJECT_NAME=$(ask "Project folder name" "laravel-app")
    DOMAIN_NAME=$(ask "Domain name (e.g. example.com)" "localhost")
    NEED_DB=$(ask "Does project use a database? (y/n)" "y")
    if [[ "$NEED_DB" =~ ^[Yy]$ ]]; then
      DB_NAME=$(ask "Database name" "laravel_db")
      DB_USER=$(ask "Database user" "laravel_user")
      DB_PASS=$(ask "Database password" "ChangeMe123!")
    fi

    install_php
    install_composer
    install_nginx_mysql
    create_database

    PROJECT_DIR="/var/www/${PROJECT_NAME}"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    log "Creating new Laravel project..."
    composer create-project laravel/laravel . || true

  else
    GIT_REPO=$(ask "Git repository URL" "")
    GIT_BRANCH=$(ask "Git branch" "main")
    PROJECT_NAME=$(ask "Project folder name" "laravel-app")
    DOMAIN_NAME=$(ask "Domain name (e.g. example.com)" "localhost")
    NEED_DB=$(ask "Does project use a database? (y/n)" "y")
    if [[ "$NEED_DB" =~ ^[Yy]$ ]]; then
      DB_NAME=$(ask "Database name" "laravel_db")
      DB_USER=$(ask "Database user" "laravel_user")
      DB_PASS=$(ask "Database password" "ChangeMe123!")
    fi

    install_php
    install_composer
    install_nginx_mysql
    create_database
    clone_project
  fi

  configure_env
  create_nginx_conf
  set_permissions

 if [[ "$DOMAIN_NAME" != "localhost" ]]; then
    log "Auto-installing SSL certificate for ${DOMAIN_NAME}..."
    install_ssl
  else
    warn "Skipping SSL (localhost detected)"
  fi

    # ========== PHPMYADMIN INSTALL ==========
    INSTALL_PHPMYADMIN=$(ask "Do you want to install phpMyAdmin? (y/n)" "y")
    if [[ "$INSTALL_PHPMYADMIN" =~ ^[Yy]$ ]]; then
      PHPMYADMIN_DOMAIN=$(ask "Enter phpMyAdmin domain (e.g. pma.example.com)" "pma.${DOMAIN_NAME}")
      PHPMYADMIN_USER=$(ask "phpMyAdmin username for login (basic auth)" "admin")
      PHPMYADMIN_PASS=$(ask "phpMyAdmin password" "ChangeMe123!")
      install_phpmyadmin
    else
      warn "phpMyAdmin installation skipped."
    fi

  log "✅ Laravel installation complete."
  echo -e "${GREEN}Visit: https://${DOMAIN_NAME}${NC}"
}

main "$@"
