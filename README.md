# 🚀 Laravel Auto Deploy Script

A professional automation script for deploying Laravel applications on Ubuntu server with Nginx, PHP, MySQL, and SSL.

![Laravel Auto Deploy](https://img.shields.io/badge/Laravel-Auto%20Deploy-FF2D20?style=for-the-badge&logo=laravel)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2F22.04-E95420?style=for-the-badge&logo=ubuntu)
![Nginx](https://img.shields.io/badge/Nginx-1.18%2B-009639?style=for-the-badge&logo=nginx)

## ✨ Features

- ✅ **Automatic Laravel Installation** (new project or from Git repository)
- 🌐 **Auto Nginx Configuration** with virtual host
- 🔒 **Free SSL Setup** with Certbot (Let's Encrypt)
- 🗄️ **Automatic MySQL Database Creation**
- 🐘 **Multiple PHP Version Support** (8.0, 8.1, 8.2, 8.3)
- 📦 **Composer and Dependency Installation**
- 🔧 **Automatic .env File Configuration**
- 👮 **Proper Permission Setup**
- 🎨 **Colorful Interactive Interface**

## 🛠 Prerequisites

- Ubuntu Server 20.04 or 22.04
- Root or sudo access
- Valid domain name (for SSL)

## 🚀 Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/MehrabSanaee/web_server_auto_config/main/installer.sh

# Make executable
chmod +x installer.sh

# Run the script
./installer.sh
```

## 📖 Complete Guide

### Method 1: Fresh Laravel Installation

1. Run the script
2. Choose option `1` for "Fresh Laravel installation"
3. Enter required information:
   - Project name
   - Domain name
   - Database settings

### Method 2: Deploy from Git Repository

1. Run the script
2. Choose option `2` for "Use GitHub repository"
3. Enter the following information:
   - Git repository URL
   - Branch name
   - Project name
   - Domain name
   - Database settings

## 🎯 Script Structure

```
📦 Laravel Auto Deploy
├── 🔐 Authentication & Access Control
├── 🖥️ OS Version Detection
├── 📦 PHP Installation (Multiple Versions)
├── 🎼 Composer Installation
├── 🌐 Nginx + MySQL Installation
├── 🗄️ Database Creation
├── 📥 Project Cloning
├── ⚙️ .env Configuration
├── 🔧 Nginx Configuration
├── 🔒 SSL Setup
└── 👮 Permission Management
```

## ⚙️ Configuration

### PHP Version Selection
The script will ask which PHP version to install:
- PHP 8.3 ✅
- PHP 8.2 ✅  
- PHP 8.1 ✅
- PHP 8.0 ✅
- other ✅

### Database Settings
```bash
Database name: laravel_db
Database user: laravel_user  
Database password: ChangeMe123!
```

### Directory Structure
```
/var/www/your-project-name/
├── public/
├── storage/
├── bootstrap/cache/
└── .env
```

## 🔧 Useful Commands After Installation

```bash
# Check service status
systemctl status nginx
systemctl status mysql
systemctl status php8.3-fpm

# View logs
tail -f /var/log/nginx/error.log
journalctl -u nginx -f

# Project configuration
cd /var/www/your-project-name
php artisan config:clear
php artisan cache:clear
```

## 🛡 Security Features

- Separate user creation for each project
- Proper directory permission setup
- Disabled default Nginx site
- Secure PHP-FPM configuration

## ❌ Troubleshooting

### Issue: Permission Errors
```bash
# Fix storage permissions
chmod -R 775 storage bootstrap/cache
chown -R www-data:your-user /var/www/your-project
```

### Issue: Database Connection
```bash
# Login to MySQL
mysql -u root -p
# Manually create user and database
```

### Issue: SSL Not Working
- Ensure domain points to server IP
- Ports 80 and 443 must be open

## 📝 Important Notes

1. **For production** always use a real domain name
2. After installation, check the `.env` file for additional configurations
3. Enable OPcache for better performance
4. Ensure regular database backups

## 🤝 Contributing

If you'd like to contribute to this script:

1. Fork the repository
2. Create a new branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

**Note**: This script is suitable for both development and production environments, but always test it before using on your main server.

<div align="center">

**Built with ❤️ for the Laravel Community**

</div>
