# Laravel VPS Auto Installer  
A lightweight, opinionated deployment script built for **my personal Laravel projects**, especially small bots and utility services.

This script is **not** intended to replace full deployment tools or CI/CD pipelines.  
Its purpose is simple: **automate repetitive VPS setup steps** I kept doing for my own Laravel-based projects.

---

## 🎯 Project Purpose

I frequently deploy small Laravel bots and private tools to fresh VPS instances.  
Repeating the same steps every time was inefficient:

- Installing PHP & extensions  
- Installing / configuring Nginx  
- Setting up SSL  
- Creating databases  
- Cloning projects  
- Running Composer, migrations, permissions, etc.  

This script was built to automate exactly those tasks — nothing more, nothing less.

It’s optimized for **speed, repeatability, and convenience**, not for complex production environments.

---

## ⚙️ Features

- PHP version selection (8.0–8.3)
- Automatic installation of PHP-FPM, Nginx, and MySQL
- Basic internet connectivity check
- Safe handling of existing nginx configs (no accidental overwrite)
- DNS validation before issuing SSL certificates
- Clone an existing Laravel repository or create a new one
- Safe `.env` updater (no messy regex replacement)
- Automatic migrations and seeders
- Nginx configuration with proper PHP-FPM socket
- Optional phpMyAdmin installation (for personal use only)
- Limited rollback (restores configs and removes incomplete projects)

---

## 🚀 Usage

```bash
sudo bash installer.sh
You will be prompted to:

Choose between creating a new Laravel project or cloning a repo

Provide domain name

Select PHP version

Enable or skip MySQL setup

Enable or skip SSL

Optionally install phpMyAdmin

🛡️ Important Notes & Limitations
This script is intentionally designed for personal use, not enterprise deployments.

It assumes a relatively clean VPS (Ubuntu/Debian)

phpMyAdmin is installed via apt, which is fine for personal use but not ideal for production

SSL is only attempted if the domain resolves to the server

Rollback is limited (restores configs and deletes incomplete project directory)

Not designed for multi-tenant or shared hosting environments

Not a substitute for Docker, Ansible, or CI/CD pipelines

If you plan to adapt it for team use or production-critical systems, consider:

Making the script modular

Improving logging

Adding backup/snapshot steps

Handling multi-instance Nginx setups

Adding non-interactive flags and configuration profiles

📁 Deployment Flow Overview
markdown
Copy code
1. Verify root + internet connectivity
2. Add PHP repository
3. Install PHP, Nginx, MySQL (optional)
4. Create or clone Laravel project
5. Generate .env safely
6. Run migrations and seeders
7. Create Nginx configuration
8. Validate DNS → issue SSL certificate
9. Install phpMyAdmin (optional)
10. Finish and output access URLs
🧩 Why I Created This Script
This wasn’t meant to be a public utility at first.
It started as a tool to speed up my own workflow:

Deploying bots quickly

Standardizing my VPS setups

Avoiding copy-pasting dozens of commands

Minimizing human errors

Keeping small side projects easy to maintain

After refining it through several deployments, it became stable enough to share.

📄 License
MIT
Feel free to use, modify, and adapt it as you wish.

🤝 Contributing
Contributions, improvements, and suggestions are welcome —
just keep in mind that the script is intentionally scoped for simple personal deployments, not enterprise automation.
