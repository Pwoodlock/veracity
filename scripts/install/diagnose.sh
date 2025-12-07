#!/bin/bash
#
# diagnose.sh - Installation diagnostic tool
# Provides comprehensive system state information for troubleshooting
#

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         VERACITY INSTALLATION DIAGNOSTICS                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

#######################################
# Check installation state
#######################################
echo -e "${CYAN}Installation State:${NC}"
if [ -f "/var/lib/veracity-installer/checkpoints" ]; then
  echo -e "${GREEN}✓ Installation state file found${NC}"
  echo ""
  echo "Completed phases:"
  grep "|completed$" /var/lib/veracity-installer/checkpoints 2>/dev/null | cut -d'|' -f2 | sed 's/^/  ✓ /' || echo "  (none)"
  echo ""

  failed_phases=$(grep "|failed$" /var/lib/veracity-installer/checkpoints 2>/dev/null | cut -d'|' -f2 || true)
  if [ -n "$failed_phases" ]; then
    echo -e "${RED}Failed phases:${NC}"
    echo "$failed_phases" | sed 's/^/  ✗ /'
    echo ""
  fi
else
  echo -e "${YELLOW}⚠ No installation state found (installation not started)${NC}"
  echo ""
fi

#######################################
# Check services
#######################################
echo -e "${CYAN}Service Status:${NC}"

check_service() {
  local service="$1"
  local display_name="${2:-$1}"

  if systemctl is-active "$service" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} ${display_name}: running"
  elif systemctl is-enabled "$service" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠${NC} ${display_name}: installed but not running"
  else
    echo -e "  ${RED}✗${NC} ${display_name}: not installed"
  fi
}

check_service postgresql "PostgreSQL"
check_service redis-server "Redis" || check_service redis "Redis"
check_service salt-master "Salt Master"
check_service salt-api "Salt API"
check_service caddy "Caddy"
check_service server-manager "Puma (Rails)"
check_service server-manager-sidekiq "Sidekiq"
echo ""

#######################################
# Check ports
#######################################
echo -e "${CYAN}Port Status:${NC}"

check_port() {
  local port="$1"
  local service="$2"

  if ss -tln | grep -q ":${port} "; then
    echo -e "  ${GREEN}✓${NC} Port ${port} (${service}): listening"
  else
    echo -e "  ${RED}✗${NC} Port ${port} (${service}): not listening"
  fi
}

check_port 5432 "PostgreSQL"
check_port 6379 "Redis"
check_port 4505 "Salt Publisher"
check_port 4506 "Salt Request Server"
check_port 8001 "Salt API"
check_port 80 "HTTP"
check_port 443 "HTTPS"
check_port 3000 "Puma"
echo ""

#######################################
# Check application
#######################################
echo -e "${CYAN}Application Status:${NC}"

if [ -d "/opt/veracity/app" ]; then
  echo -e "  ${GREEN}✓${NC} Application directory exists"

  if [ -f "/opt/veracity/app/.env.production" ]; then
    echo -e "  ${GREEN}✓${NC} Environment file exists"
  else
    echo -e "  ${RED}✗${NC} Environment file missing"
  fi

  if [ -f "/opt/veracity/app/config/database.yml" ]; then
    echo -e "  ${GREEN}✓${NC} Database config exists"
  else
    echo -e "  ${RED}✗${NC} Database config missing"
  fi

  if [ -d "/opt/veracity/app/vendor/bundle" ]; then
    echo -e "  ${GREEN}✓${NC} Gems installed"
  else
    echo -e "  ${RED}✗${NC} Gems not installed"
  fi
else
  echo -e "  ${RED}✗${NC} Application directory not found"
fi
echo ""

#######################################
# Check Ruby
#######################################
echo -e "${CYAN}Ruby Status:${NC}"

if [ -f "/home/deploy/.rbenv/bin/rbenv" ]; then
  echo -e "  ${GREEN}✓${NC} rbenv installed"

  if sudo -u deploy bash -c "source /home/deploy/.rbenv/etc/bashrc && rbenv version" >/dev/null 2>&1; then
    ruby_version=$(sudo -u deploy bash -c "source /home/deploy/.rbenv/etc/bashrc && rbenv version" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} Ruby version: ${ruby_version}"
  else
    echo -e "  ${YELLOW}⚠${NC} Ruby not available"
  fi
else
  echo -e "  ${RED}✗${NC} rbenv not installed"
fi
echo ""

#######################################
# Check Node.js
#######################################
echo -e "${CYAN}Node.js Status:${NC}"

if command -v node >/dev/null 2>&1; then
  node_version=$(node --version)
  echo -e "  ${GREEN}✓${NC} Node.js version: ${node_version}"
else
  echo -e "  ${RED}✗${NC} Node.js not installed"
fi
echo ""

#######################################
# Check connectivity
#######################################
echo -e "${CYAN}Connectivity Tests:${NC}"

# PostgreSQL
if sudo -u postgres psql -c '\l' >/dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} PostgreSQL: accessible"
else
  echo -e "  ${RED}✗${NC} PostgreSQL: not accessible"
fi

# Redis
if redis-cli ping >/dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Redis: accessible"
else
  echo -e "  ${RED}✗${NC} Redis: not accessible"
fi

# Salt API
if curl -sSf http://127.0.0.1:8001 -o /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Salt API: accessible"
else
  echo -e "  ${RED}✗${NC} Salt API: not accessible"
fi

# Rails app
if curl -sSf http://localhost:3000/up -o /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Rails app: responding"
else
  echo -e "  ${RED}✗${NC} Rails app: not responding"
fi
echo ""

#######################################
# Check logs for errors
#######################################
echo -e "${CYAN}Recent Errors:${NC}"

if [ -f "/var/lib/veracity-installer/errors.log" ]; then
  error_count=$(wc -l < /var/lib/veracity-installer/errors.log)
  if [ "$error_count" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} ${error_count} errors logged"
    echo ""
    echo "  Last 5 errors:"
    tail -n 5 /var/lib/veracity-installer/errors.log | sed 's/^/    /'
  else
    echo -e "  ${GREEN}✓${NC} No errors logged"
  fi
else
  echo "  (no error log found)"
fi
echo ""

#######################################
# Check disk space
#######################################
echo -e "${CYAN}System Resources:${NC}"

free_space=$(df -h / | awk 'NR==2 {print $4}')
echo "  Disk space available: ${free_space}"

mem_available=$(free -h | awk '/^Mem:/ {print $7}')
echo "  Memory available: ${mem_available}"

load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
echo "  Load average: ${load_avg}"
echo ""

#######################################
# Recommendations
#######################################
echo -e "${CYAN}Next Steps:${NC}"

if [ -f "/var/lib/veracity-installer/checkpoints" ]; then
  if grep -q "|failed$" /var/lib/veracity-installer/checkpoints 2>/dev/null; then
    echo "  1. Review error log: /var/lib/veracity-installer/errors.log"
    echo "  2. Check service logs: journalctl -u <service-name> -n 50"
    echo "  3. Fix reported issues"
    echo "  4. Resume installation: sudo ./install.sh --resume"
  elif grep -q "|completed$" /var/lib/veracity-installer/checkpoints 2>/dev/null; then
    last_phase=$(grep "|completed$" /var/lib/veracity-installer/checkpoints | tail -1 | cut -d'|' -f2)
    echo "  Installation in progress. Last completed phase: ${last_phase}"
    echo "  Resume installation: sudo ./install.sh --resume"
  fi
else
  echo "  Start installation: sudo ./install.sh"
fi
echo ""

#######################################
# Detailed logs location
#######################################
echo -e "${CYAN}Log Files:${NC}"
echo "  Installation log: /var/log/veracity-install.log"
echo "  Error log: /var/lib/veracity-installer/errors.log"
echo "  Checkpoint file: /var/lib/veracity-installer/checkpoints"
echo "  Rollback script: /var/lib/veracity-installer/rollback.sh"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
