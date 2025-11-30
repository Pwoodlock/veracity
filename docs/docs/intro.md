---
sidebar_position: 1
---

# Getting Started

Welcome to **Veracity** - a modern server management platform built with Ruby on Rails and SaltStack.

:::caution Alpha Software
Version 0.0.1-alpha is in early development. Features and APIs may change.
:::

## What is Veracity?

Veracity is a web-based infrastructure management platform that provides:

- **Centralized Server Management** - Monitor and manage multiple servers from a single dashboard
- **Task Automation** - Execute Salt commands with 36+ pre-built templates
- **Real-time Updates** - WebSocket-based live feedback on task execution
- **[Security Monitoring](./features/vulnerability-lookup)** - CVE vulnerability scanning via CIRCL's Vulnerability Lookup
- **[Proxmox Integration](./integrations/proxmox)** - VM/LXC power management and snapshots via Proxmoxer
- **Cloud Integration** - Hetzner Cloud API support
- **[NetBird Integration](./integrations/netbird)** - Deploy zero-trust network agents across your infrastructure
- **Push Notifications** - Gotify integration for alerts

## Quick Start

### Prerequisites

Before installing, ensure your system meets these requirements:

| Requirement | Specification |
|-------------|---------------|
| **OS** | Ubuntu 20.04/22.04/24.04 or Debian 11/12 |
| **CPU** | 2 cores minimum |
| **RAM** | 2 GB minimum (4 GB recommended) |
| **Disk** | 20 GB free space |
| **Network** | Static IP or FQDN |
| **Access** | Root or sudo privileges |

### Installation

**One-line install:**

```bash
curl -sSL https://raw.githubusercontent.com/Pwoodlock/veracity-/main/install.sh | sudo bash
```

**Or clone and run:**

```bash
git clone https://github.com/Pwoodlock/veracity-.git
cd veracity-
sudo ./install.sh
```

The interactive installer will:

1. Detect your operating system
2. Prompt for configuration (domain, admin credentials)
3. Install all dependencies
4. Configure services (PostgreSQL, Redis, SaltStack, Caddy)
5. Deploy the application
6. Set up systemd services and firewall

**Installation time:** ~15-20 minutes

### What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.3.6 | Application runtime (via Mise) |
| Rails | 8.0 | Web framework |
| DaisyUI | 5.x | UI components (Tailwind CSS) |
| Node.js | 24 LTS | Asset compilation |
| PostgreSQL | 14+ | Database |
| Redis | 7+ | Cache & job queue |
| SaltStack | 3007 | Infrastructure automation |
| Caddy | Latest | Web server with auto-HTTPS |
| Gotify | Latest | Push notifications |

## After Installation

Once installation completes:

1. **Access the dashboard** at `https://your-domain.com`
2. **Login** with credentials from `/tmp/veracity-install-credentials-*.txt`
3. **Enable 2FA** in Settings → Security
4. **Install Salt minions** on servers you want to manage:
   ```bash
   curl -sSL https://your-domain.com/install-minion.sh | sudo bash
   ```
5. **Accept minion keys** in the Onboarding page

## Need Help?

- [GitHub Issues](https://github.com/Pwoodlock/veracity-/issues)
- [GitHub Discussions](https://github.com/Pwoodlock/veracity-/discussions)
