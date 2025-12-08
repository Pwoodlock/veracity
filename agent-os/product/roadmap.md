# Product Roadmap

## Completed (Phase 1: Core Platform)

1. [x] Dashboard and Server Overview - Real-time server status dashboard with metrics, activity charts, and health monitoring via Action Cable WebSockets `M`
2. [x] Salt Minion Management - Accept/reject minion keys, ping servers, sync grains, and execute Salt commands `M`
3. [x] User Authentication - Devise-based authentication with 2FA (TOTP), backup codes, and OAuth support `M`
4. [x] Server Groups - Create groups, assign servers, bulk operations on grouped servers `S`
5. [x] Task System - Create tasks from 36+ templates, schedule execution, view task run history with output `L`
6. [x] Command Execution - Execute Salt commands with output formatting, history tracking, and user attribution `M`
7. [x] CVE Watchlists - Create vendor/product watchlists, configure scan schedules, test API connectivity `M`
8. [x] Vulnerability Alerts - Display alerts by severity, acknowledge/resolve/ignore workflows, CVSS scoring `M`
9. [x] Hetzner Cloud Integration - Server discovery, power control, snapshot management via Python API `M`
10. [x] Proxmox VE Integration - VM/LXC control, snapshots, secure pillar-based API authentication `L`
11. [x] Gotify Notifications - Push notification configuration, application management, alert delivery `S`
12. [x] Salt State Editor - Create/edit/deploy Salt states, template library, YAML validation `M`
13. [x] Backup Configuration - Borg backup setup, scheduling, history tracking `S`

## In Progress (Phase 2: Enhanced Security and Automation)

14. [ ] EPSS Score Display - Show Exploit Prediction Scoring System scores on vulnerability alerts to prioritize remediation `S`
15. [ ] CISA KEV Highlighting - Visually distinguish Known Exploited Vulnerabilities with special badge and filtering `S`
16. [ ] Bulk Vulnerability Actions - Select multiple alerts and bulk acknowledge/resolve with single action `S`
17. [ ] Server Vulnerability Summary - Per-server view showing all active CVEs affecting that server with remediation status `M`
18. [ ] CVE Scan Scheduling - Configure per-watchlist scan intervals (hourly, daily, weekly) with next-run display `S`
19. [ ] NetBird VPN Deployment - Deploy NetBird agents to minions via Salt states with secure pillar-based setup keys `M`
20. [ ] Salt State Versioning - Track changes to Salt states with diff view and rollback capability `M`

## Planned (Phase 3: Operational Excellence)

21. [ ] Multi-Minion Command Execution - Execute commands against glob patterns (e.g., `web-*`) or groups with parallel execution `M`
22. [ ] Command Output Streaming - Real-time command output via WebSockets for long-running operations `M`
23. [ ] Task Execution Reports - Email/Gotify summary reports after scheduled task runs with success/failure counts `S`
24. [ ] Server Compliance Dashboard - Aggregate view of patching status, vulnerability counts, and drift detection `L`
25. [ ] Automated Patch Scheduling - Configure maintenance windows for automatic security/full updates per group `M`
26. [ ] Audit Log - Comprehensive audit trail of all user actions (commands, config changes, logins) with search/filter `M`
27. [ ] API Rate Limiting Dashboard - View and configure rate limits for external API integrations (Hetzner, Proxmox, CVE) `S`

## Future (Phase 4: Enterprise Features)

28. [ ] Multi-Tenant Support - Separate organizations/tenants with isolated server pools and user management `XL`
29. [ ] LDAP/Active Directory Integration - Enterprise SSO via LDAP with group-based role mapping `L`
30. [ ] Webhook Integrations - Outbound webhooks for events (server offline, critical CVE, task failure) to Slack/Teams/PagerDuty `M`
31. [ ] Custom Dashboard Widgets - User-configurable dashboard with draggable widgets and saved layouts `L`
32. [ ] Server Cost Tracking - Track and display cloud costs from Hetzner API with budget alerts `M`
33. [ ] Ansible Playbook Support - Import and execute Ansible playbooks alongside Salt states `L`
34. [ ] High Availability Mode - Active-passive failover for Veracity itself with shared database `XL`
35. [ ] REST API - Full REST API for external integrations with API key authentication and rate limiting `L`

> Notes
> - Order items by technical dependencies and product architecture
> - Each item should represent an end-to-end (frontend + backend) functional and testable feature
> - Effort scale: XS (1 day), S (2-3 days), M (1 week), L (2 weeks), XL (3+ weeks)
> - Phase 1 items are marked complete based on existing codebase analysis
> - Phase 2 focuses on hardening existing security features and adding automation
> - Phase 3 builds operational maturity with compliance and reporting
> - Phase 4 targets enterprise adoption with multi-tenancy and integrations
