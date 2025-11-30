<div align="center">

![Veracity Logo](docs/static/img/logo.svg)

**Modern Server Management Platform**

[![Version](https://img.shields.io/badge/version-0.0.1--alpha-blue.svg)](https://github.com/Pwoodlock/veracity-)
[![Ruby](https://img.shields.io/badge/Ruby-3.3.6-CC342D.svg?logo=ruby)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/Rails-8.0-CC0000.svg?logo=rubyonrails)](https://rubyonrails.org/)
[![SaltStack](https://img.shields.io/badge/SaltStack-3007-57BCAD.svg)](https://saltproject.io/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A comprehensive infrastructure management platform built with Ruby on Rails and SaltStack API, External API Services.

[**Documentation**](https://pwoodlock.github.io/veracity-/) · [**Quick Start**](#quick-start) · [**Features**](#features)

</div>

---

> **Alpha Software** - This project is in early development. APIs and features may change.

## Quick Start

### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/Pwoodlock/veracity-/main/install.sh | sudo bash
```

### Clone and Install

```bash
git clone https://github.com/Pwoodlock/veracity-.git
cd veracity-
sudo ./install.sh
```

The interactive installer handles everything: dependencies, database, services, and configuration.

**Installation time:** ~15-20 minutes

---

## Features

| Feature | Description |
|---------|-------------|
| **Server Management** | Monitor and manage servers via Salt minions |
| **Task Automation** | Run Salt commands with 36+ pre-built templates |
| **Real-time Updates** | WebSocket-based live task execution feedback |
| **Security Scanning** | CVE vulnerability monitoring |
| **Push Notifications** | Gotify integration for alerts |
| **Cloud APIs** | Hetzner Cloud & Proxmox VE integration |
| **Modern UI** | DaisyUI + Tailwind CSS responsive dashboard |

---

## System Requirements

### Supported Operating Systems

| OS | Versions |
|----|----------|
| **Ubuntu** | 20.04, 22.04, 24.04 LTS |
| **Debian** | 11 (Bullseye), 12 (Bookworm) |

> RHEL-based distributions (Rocky Linux, AlmaLinux) support planned.

### Hardware

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 2 GB | 4+ GB |
| Disk | 20 GB | 50+ GB |

### Software Stack

| Component | Version | Notes |
|-----------|---------|-------|
| Ruby | 3.3.6 | Via Mise version manager |
| Rails | 8.0 | Web framework |
| DaisyUI | 5.x | UI component library (Tailwind CSS) |
| Node.js | 24 LTS | Asset compilation |
| PostgreSQL | 14+ | Database |
| Redis | 7+ | Cache & job queue |
| SaltStack | 3007 | Infrastructure automation |
| Caddy | Latest | Web server with auto-HTTPS |

---

## Post-Installation

After installation completes:

1. Access the dashboard at `https://your-domain.com`
2. Login with credentials from `/tmp/veracity-install-credentials-*.txt`
3. Enable 2FA in Settings → Security
4. Install Salt minions on servers to manage:
   ```bash
   curl -sSL https://your-domain.com/install-minion.sh | sudo bash
   ```
5. Accept minion keys in the Onboarding page

---

## Installation Options

```bash
# Resume after error
sudo ./install.sh --resume

# Rollback changes
sudo ./install.sh --rollback
```

---

## Documentation

- **Full Documentation:** https://pwoodlock.github.io/veracity-/
- **Installation Guide:** [INSTALLATION.md](INSTALLATION.md)

---

## Support

- **Issues:** https://github.com/Pwoodlock/veracity-/issues
- **Discussions:** https://github.com/Pwoodlock/veracity-/discussions

---

## License

[MIT License](LICENSE)
