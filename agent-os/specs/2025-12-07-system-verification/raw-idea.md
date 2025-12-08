# Raw Idea: System Verification & Validation Suite

## Overview

Create a comprehensive verification and validation suite to ensure all existing Veracity features are working correctly, GitHub workflows are functioning, and the entire CI/CD pipeline integrates properly.

## Goals

1. Verify all existing features work correctly
2. Fix and enhance GitHub Actions workflows
3. Add automated testing (unit, integration, system tests)
4. Include security testing
5. Set up runtime health checks for production monitoring
6. Set up Docusaurus local development environment

## Scope

### Features to Verify
- Server Management via Salt Stack (minion management, key acceptance, ping)
- Dashboard with real-time server status and metrics
- CVE/Vulnerability Monitoring (watchlists, alerts, API integration)
- Proxmox Integration (VM listing, snapshots)
- Hetzner Integration (cloud servers, snapshots)
- NetBird Integration (VPN setup keys, deployment)
- Gotify Integration (push notifications)
- Backup Management (Borg backup configuration)
- Task System (scheduled tasks, templates, execution)
- Salt State Management (custom states, CLI interface)
- User Management (authentication, 2FA, roles)
- Groups functionality

### GitHub Workflows to Fix
- ci.yml - Fix docs job condition
- claude.yml - Add write permissions
- claude-code-review.yml - Add pull-requests: write permission
- deploy-docs.yml - Fix Node.js version (24 -> 20)

### Security Tests to Include
1. CSRF Protection Verification
2. SQL Injection Testing
3. Command Injection Testing
4. Session Security
5. Authorization Testing (Pundit)
6. Encrypted Credentials Verification
7. Rate Limiting Verification

## Test Environment

- **Staging Server**: 46.224.101.253 (can be reset via installer)
- **Test Minion**: n8n (safe for destructive tests)
- **Test Framework**: Minitest (enhance existing)
- **Test Strategy**: Factory-based test data with database transaction rollback

## Requirements Gathered

### Testing Approach
- Automated tests (unit, integration, system) - not just manual checklists
- Tests run directly on server (not via SSH) for speed
- SSH used for deployment verification and infrastructure health checks
- Factory-based test data that cleans up after itself

### Success Criteria
- Functional correctness and error handling (not performance benchmarks)
- All security tests pass
- Runtime health checks operational
- CI/CD pipeline fully functional with Claude integration

## Additional Tasks
- Set up Docusaurus development environment in WSL
- Ensure GitHub Pages deployment works
