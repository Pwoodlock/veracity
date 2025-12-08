#!/bin/bash
# Verification script for fresh Veracity installation
# Run this AFTER the installer completes to verify Salt templates auto-seeding

echo "==================================="
echo "Veracity Fresh Install Verification"
echo "==================================="
echo ""

# Check if running on the server
if [ ! -d "/opt/veracity/app" ]; then
  echo "❌ Error: /opt/veracity/app not found"
  echo "   This script must run on the Veracity server after installation"
  exit 1
fi

cd /opt/veracity/app

echo "1. Checking database connection..."
if sudo -u deploy bash -c "cd /opt/veracity/app && source ~/.bashrc && RAILS_ENV=production /home/deploy/.local/share/mise/shims/bundle exec rails runner 'ActiveRecord::Base.connection'" &>/dev/null; then
  echo "   ✅ Database connected"
else
  echo "   ❌ Database connection failed"
  exit 1
fi

echo ""
echo "2. Checking Salt State templates..."
TEMPLATE_COUNT=$(sudo -u deploy bash -c "cd /opt/veracity/app && source ~/.bashrc && RAILS_ENV=production /home/deploy/.local/share/mise/shims/bundle exec rails runner 'puts SaltState.templates.count'" 2>/dev/null | tail -1)

if [ "$TEMPLATE_COUNT" = "15" ]; then
  echo "   ✅ All 15 templates seeded automatically"
else
  echo "   ❌ Expected 15 templates, found: $TEMPLATE_COUNT"
  exit 1
fi

echo ""
echo "3. Verifying template categories..."
sudo -u deploy bash -c "cd /opt/veracity/app && source ~/.bashrc && RAILS_ENV=production /home/deploy/.local/share/mise/shims/bundle exec rails runner \"
puts '   Categories:'
SaltState.templates.group(:category).count.sort.each { |c, n| puts '     ' + c + ': ' + n.to_s }
\"" 2>/dev/null | tail -10

echo ""
echo "4. Checking services..."
if systemctl is-active --quiet server-manager; then
  echo "   ✅ server-manager running"
else
  echo "   ⚠️  server-manager not running"
fi

if systemctl is-active --quiet server-manager-sidekiq; then
  echo "   ✅ server-manager-sidekiq running"
else
  echo "   ⚠️  server-manager-sidekiq not running"
fi

echo ""
echo "5. Checking web access..."
if curl -sf http://localhost:3000/up > /dev/null 2>&1; then
  echo "   ✅ Web application responding"
else
  echo "   ⚠️  Web application not responding"
fi

echo ""
echo "==================================="
echo "✅ Fresh Installation Verified!"
echo "==================================="
echo ""
echo "Next steps:"
echo "  1. Access web UI at: https://your-domain.com"
echo "  2. Navigate to: Salt Editor → Templates"
echo "  3. Verify 15 templates are visible grouped by category"
echo ""
