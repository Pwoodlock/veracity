#!/bin/bash
#
# Server Manager - Database Setup Helper Script
# Run this after deploying the application to initialize the production database
#
# Usage: ./scripts/setup-database.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as deploy user
if [ "$(whoami)" != "deploy" ]; then
  print_error "This script must be run as the deploy user"
  print_info "Run: su - deploy"
  print_info "Then: cd /opt/veracity/app && ./scripts/setup-database.sh"
  exit 1
fi

# Check if in correct directory
if [ ! -f "config/database.yml" ]; then
  print_error "Must be run from application root directory"
  print_info "Run: cd /opt/veracity/app"
  exit 1
fi

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
  print_error ".env.production file not found"
  print_info "Create it first: cp .env.production.example .env.production"
  print_info "Then configure all required values"
  exit 1
fi

echo ""
print_info "╔══════════════════════════════════════════════════════════════╗"
print_info "║  Server Manager - Database Setup                             ║"
print_info "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Load environment
export RAILS_ENV=production
export $(cat .env.production | grep -v '^#' | xargs)

print_info "Environment: $RAILS_ENV"
echo ""

# Step 1: Create database
print_info "[1/5] Creating database..."
if rails db:create 2>/dev/null; then
  print_success "Database created"
else
  print_warning "Database may already exist (this is okay)"
fi

# Step 2: Run migrations
print_info "[2/5] Running database migrations..."
rails db:migrate
print_success "Migrations complete"

# Step 3: Load schema (if migrations failed)
if [ $? -ne 0 ]; then
  print_warning "Migrations had issues, trying schema load..."
  rails db:schema:load
fi

# Step 4: Create admin user
print_info "[3/5] Creating admin user..."
echo ""
print_warning "Please provide admin user details:"
echo ""

read -p "Admin Email: " admin_email
while true; do
  read -s -p "Admin Password (min 12 chars): " admin_password
  echo ""
  read -s -p "Confirm Password: " admin_password_confirm
  echo ""

  if [ "$admin_password" = "$admin_password_confirm" ]; then
    if [ ${#admin_password} -ge 12 ]; then
      break
    else
      print_error "Password must be at least 12 characters"
    fi
  else
    print_error "Passwords do not match"
  fi
done

read -p "Admin Name [Admin User]: " admin_name
admin_name=${admin_name:-"Admin User"}

# Create admin user via Rails console
rails runner "
begin
  user = User.create!(
    email: '${admin_email}',
    password: '${admin_password}',
    password_confirmation: '${admin_password}',
    role: 'admin',
    name: '${admin_name}'
  )
  puts '✓ Admin user created successfully'
rescue ActiveRecord::RecordInvalid => e
  puts '✗ Error creating user:'
  puts e.message
  exit 1
rescue => e
  puts '✗ Unexpected error:'
  puts e.message
  exit 1
end
"

if [ $? -eq 0 ]; then
  print_success "Admin user created"
else
  print_error "Failed to create admin user"
  print_info "You can create it manually later using Rails console"
fi

# Step 5: Verify setup
print_info "[4/5] Verifying database setup..."

DB_CHECK=$(rails runner "
puts 'Servers: ' + Server.count.to_s
puts 'Users: ' + User.count.to_s
puts 'Commands: ' + Command.count.to_s
")

echo "$DB_CHECK"
print_success "Database verification complete"

# Step 6: Display summary
print_info "[5/5] Setup Summary"
echo ""
print_success "╔══════════════════════════════════════════════════════════════╗"
print_success "║  Database Setup Complete!                                    ║"
print_success "╚══════════════════════════════════════════════════════════════╝"
echo ""
print_info "Next Steps:"
print_info ""
print_info "1. Precompile assets (if not done):"
print_info "   RAILS_ENV=production rails assets:precompile"
print_info ""
print_info "2. Start services:"
print_info "   sudo systemctl start server-manager"
print_info "   sudo systemctl start server-manager-sidekiq"
print_info ""
print_info "3. Check service status:"
print_info "   sudo systemctl status server-manager"
print_info ""
print_info "4. Access your application:"
print_info "   https://\${DOMAIN:-your-domain.com}/avo"
print_info ""
print_info "5. Login with:"
print_info "   Email: ${admin_email}"
print_info "   Password: (the password you just created)"
echo ""
print_success "Setup complete!"
