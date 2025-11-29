# Laravel VPS Auto Installer

A lightweight, opinionated deployment script built for **my personal
Laravel projects**, especially small tools, micro-services, and private
applications.

This script is not intended to replace DevOps tools like Docker,
Deployer, Ansible, or CI/CD pipelines.\
It exists for one reason: **to automate repetitive VPS setup tasks for
my own workflow** and speed up deployments on fresh servers.

------------------------------------------------------------------------

## 🎯 Purpose

I regularly deploy small Laravel projects and utilities to new VPS instances.
Repeating the same installation steps manually was inefficient and prone to human error.

This script automates:

-   PHP installation (multiple versions supported)
-   Nginx installation and configuration
-   SSL setup (DNS-validated)
-   MySQL installation and database creation
-   Creating or cloning a Laravel project
-   Running Composer
-   Generating a clean and safe `.env`
-   Running migrations and seeders
-   Setting proper permissions

Designed for **quick, personal deployments**, not full enterprise
environments.

------------------------------------------------------------------------

## ⚙️ Features

-   PHP version selector (8.0--8.3)
-   Automated installation: PHP-FPM, Nginx, MySQL
-   Internet connectivity check
-   Safe Nginx configuration (no accidental overwrites)
-   DNS verification before issuing SSL certificates
-   Create or clone Laravel projects
-   Safe `.env` key/value management
-   Automatic migrations & seeders
-   Optional phpMyAdmin installation
-   Limited rollback for incomplete installs

------------------------------------------------------------------------

## 🚀 Usage

``` bash
sudo bash installer.sh
```

The script will interactively guide you through:

-   Creating a new Laravel project or cloning a Git repo\
-   Setting a domain name\
-   Enabling or skipping MySQL\
-   Enabling or skipping SSL\
-   Selecting PHP version\
-   Optional phpMyAdmin setup

------------------------------------------------------------------------

## ⚠️ Notes & Limitations

This script is intentionally scoped for **personal projects**.

-   Works best on a clean VPS (Ubuntu/Debian)
-   phpMyAdmin installation via apt is for personal/light use only
-   Rollback is limited to restoring Nginx config and removing
    incomplete directories
-   Not suitable for multi-project or multi-domain production servers
-   Not a replacement for professional DevOps tooling

For production or team environments, consider:

-   Modularizing the script\
-   Improving logging\
-   Adding backup/snapshot logic\
-   Adding non-interactive flags\
-   Integrating with CI/CD

------------------------------------------------------------------------

## 📁 Deployment Process Overview

    1. Verify root access + internet connectivity
    2. Add PHP repository
    3. Install PHP, Nginx, MySQL
    4. Create or clone Laravel project
    5. Generate .env safely
    6. Run migrations / seeders
    7. Configure Nginx
    8. Validate DNS → generate SSL certificate
    9. Optional phpMyAdmin installation
    10. Output final URLs and status

------------------------------------------------------------------------

## 🧩 Why I Built This Script

Because I kept deploying the same kind of Laravel projects to VPS
servers again and again.\
Typing 20--30 commands each time was a waste of time.

This script helps me:

-   Deploy much faster\
-   Keep deployments consistent\
-   Reduce mistakes\
-   Spend more time coding instead of configuring

------------------------------------------------------------------------

## 📄 License

MIT --- free to use, modify, and adapt.

------------------------------------------------------------------------

## 🤝 Contributing

Contributions and improvements are welcome.\
Just note that the script's core purpose is to remain a **simple,
personal deployment helper for small Laravel projects**.
