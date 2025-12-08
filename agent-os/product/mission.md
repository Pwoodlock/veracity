# Product Mission

## Pitch

**Veracity** is a modern server management platform that helps DevOps engineers, system administrators, and security teams manage their infrastructure at scale by providing a unified interface for server orchestration, security monitoring, and cloud integration through SaltStack automation.

## Users

### Primary Customers

- **Small to Medium IT Teams**: Organizations with 5-500 servers needing centralized management without enterprise complexity
- **DevOps Engineers**: Technical teams managing hybrid infrastructure (on-premise + cloud)
- **Managed Service Providers (MSPs)**: Companies managing multiple client environments
- **Security-Conscious Organizations**: Teams requiring CVE monitoring and compliance visibility

### User Personas

**DevOps Engineer** (25-45)
- **Role:** Infrastructure Engineer / Site Reliability Engineer
- **Context:** Manages 50-200 servers across Hetzner Cloud, Proxmox clusters, and bare metal
- **Pain Points:** Jumping between multiple dashboards (Hetzner console, Proxmox UI, monitoring tools), no unified view of infrastructure health, manual update coordination across servers
- **Goals:** Single pane of glass for all infrastructure, automated security updates, quick incident response

**System Administrator** (30-50)
- **Role:** IT Systems Administrator / Infrastructure Manager
- **Context:** Responsible for server uptime, security patching, and compliance at a mid-size company
- **Pain Points:** Tracking CVEs manually, missing critical security updates, no visibility into which servers are vulnerable
- **Goals:** Proactive vulnerability alerts, automated patching workflows, audit trail for compliance

**Security Team Lead** (35-55)
- **Role:** Security Operations / IT Security Manager
- **Context:** Oversees security posture across the organization's server fleet
- **Pain Points:** No real-time CVE tracking, difficulty correlating vulnerabilities to specific servers, manual remediation tracking
- **Goals:** CVE watchlists by vendor/product, CVSS-based prioritization, exploited vulnerability alerts

## The Problem

### Fragmented Infrastructure Management

Modern IT teams manage infrastructure across multiple platforms (cloud providers, on-premise hypervisors, bare metal) but lack a unified management interface. This forces engineers to:
- Switch between 3-5 different management consoles daily
- Manually track server status across disconnected systems
- Coordinate updates without centralized orchestration
- Miss critical security vulnerabilities due to information silos

**Impact:** 40% of security breaches involve unpatched vulnerabilities. Teams waste 10+ hours weekly on manual infrastructure coordination.

**Our Solution:** A single Rails-based platform that unifies server management through SaltStack automation, integrates with major cloud providers (Hetzner, Proxmox), and provides proactive CVE monitoring with automated alerting.

### Security Visibility Gap

Organizations struggle to maintain visibility into their security posture across distributed infrastructure. Traditional vulnerability scanners are expensive, complex, and often disconnected from configuration management.

**Our Solution:** Built-in CVE monitoring via PyVulnerabilityLookup integration with vendor/product watchlists, CVSS scoring, EPSS probability tracking, and CISA Known Exploited Vulnerabilities (KEV) alerts.

## Differentiators

### SaltStack-Native Architecture

Unlike agent-based monitoring tools or SSH-based solutions, Veracity is built on SaltStack from the ground up. This provides:
- Sub-second command execution to thousands of minions
- State-based configuration management (not just monitoring)
- Event-driven automation with pillar-based secret management
- 36+ pre-built task templates for common operations

**Result:** 10x faster operations than SSH-based tools, with enterprise-grade security (no SSH keys to manage).

### Integrated Cloud Provider Support

Unlike generic monitoring tools, Veracity provides deep integration with specific cloud platforms:
- **Hetzner Cloud**: Server power control, snapshots, real-time status
- **Proxmox VE**: VM/LXC management, snapshot rollback, secure API integration via Salt pillar
- **NetBird**: Zero-trust VPN deployment via Salt states with secure key management

**Result:** Cloud operations from within the same interface as server management, with full audit trail.

### Security-First CVE Monitoring

Unlike traditional vulnerability scanners that require network scanning, Veracity:
- Monitors CVEs by vendor/product watchlists (proactive vs reactive)
- Integrates with PyVulnerabilityLookup for real-time CVE data
- Tracks EPSS scores (Exploit Prediction Scoring System)
- Alerts on CISA Known Exploited Vulnerabilities
- Correlates vulnerabilities to specific servers in your fleet

**Result:** Know about vulnerabilities before they're exploited, with clear remediation paths.

## Key Features

### Core Features

- **Real-Time Dashboard**: Server status overview with health metrics, uptime, and activity charts via WebSockets
- **Salt Minion Management**: Accept/reject keys, ping servers, sync grains, execute Salt commands
- **Server Groups**: Organize servers by environment, location, or function with bulk operations
- **Task System**: Scheduled and on-demand task execution with 36+ templates (updates, backups, maintenance)
- **Salt CLI Interface**: Full Salt command access with history and output formatting

### Security Features

- **CVE Watchlists**: Monitor specific vendors/products for new vulnerabilities
- **Vulnerability Alerts**: Severity-based alerts (Critical, High, Medium, Low) with CVSS scoring
- **Exploited CVE Tracking**: CISA KEV integration for actively exploited vulnerabilities
- **Two-Factor Authentication**: TOTP-based 2FA with backup codes
- **Role-Based Access Control**: Admin, Operator, and Viewer roles with Pundit policies

### Cloud Integration Features

- **Hetzner Cloud**: Power control (start/stop/reboot), snapshot management, server discovery
- **Proxmox VE**: VM/LXC control, snapshot create/rollback/delete, secure pillar-based API authentication
- **NetBird VPN**: Deploy NetBird agents to minions via Salt states with secure setup key handling
- **Gotify Notifications**: Push notification integration for alerts and task completion

### Automation Features

- **System Updates**: Check, security-only, or full update workflows across fleet
- **Backup Management**: Borg backup configuration with scheduling and history
- **Salt State Editor**: Create, edit, test, and deploy Salt states from the UI
- **Metrics Collection**: Scheduled CPU, memory, disk metrics with historical charting
