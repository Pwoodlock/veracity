# frozen_string_literal: true

# Salt Templates Seed File
# Run with: rails db:seed:salt_templates

puts "Seeding Salt Templates..."

# Helper to create or update templates
def seed_template(attrs)
  state = SaltState.find_or_initialize_by(name: attrs[:name], state_type: attrs[:state_type])
  state.assign_attributes(attrs.merge(is_template: true))
  if state.save
    puts "  ✓ #{attrs[:state_type]}: #{attrs[:name]}"
  else
    puts "  ✗ #{attrs[:state_type]}: #{attrs[:name]} - #{state.errors.full_messages.join(', ')}"
  end
end

# =============================================================================
# Base System States
# =============================================================================

seed_template(
  name: 'base/init',
  state_type: :state,
  category: 'base',
  description: 'Base system configuration with timezone, locale, and essential packages',
  content: <<~YAML
    # Base System Configuration
    # Sets timezone, installs essential packages, and configures basic system settings

    {% set timezone = pillar.get('system:timezone', 'UTC') %}

    # Set timezone
    timezone:
      timezone.system:
        - name: {{ timezone }}

    # Install essential packages
    base_packages:
      pkg.installed:
        - pkgs:
          - curl
          - wget
          - vim
          - htop
          - git
          - unzip
          - net-tools
          - dnsutils
          - jq

    # Enable automatic security updates (Debian/Ubuntu)
    {% if grains['os_family'] == 'Debian' %}
    unattended-upgrades:
      pkg.installed: []

    /etc/apt/apt.conf.d/20auto-upgrades:
      file.managed:
        - contents: |
            APT::Periodic::Update-Package-Lists "1";
            APT::Periodic::Unattended-Upgrade "1";
            APT::Periodic::AutocleanInterval "7";
        - require:
          - pkg: unattended-upgrades
    {% endif %}

    # Set system locale
    {% if grains['os_family'] == 'Debian' %}
    locale_gen:
      cmd.run:
        - name: locale-gen en_US.UTF-8
        - unless: locale -a | grep -q en_US.utf8
    {% endif %}
  YAML
)

seed_template(
  name: 'base/users',
  state_type: :state,
  category: 'base',
  description: 'User management - create users from pillar data',
  content: <<~YAML
    # User Management
    # Creates users defined in pillar['users']

    {% for user, config in pillar.get('users', {}).items() %}
    {{ user }}:
      user.present:
        - name: {{ user }}
        - shell: {{ config.get('shell', '/bin/bash') }}
        - home: {{ config.get('home', '/home/' + user) }}
        - createhome: True
        {% if config.get('groups') %}
        - groups:
          {% for group in config.get('groups', []) %}
          - {{ group }}
          {% endfor %}
        {% endif %}
        {% if config.get('uid') %}
        - uid: {{ config.get('uid') }}
        {% endif %}

    {% if config.get('ssh_keys') %}
    {{ user }}_ssh_keys:
      ssh_auth.present:
        - user: {{ user }}
        - names:
          {% for key in config.get('ssh_keys', []) %}
          - {{ key }}
          {% endfor %}
        - require:
          - user: {{ user }}
    {% endif %}
    {% endfor %}
  YAML
)

# =============================================================================
# Security States
# =============================================================================

seed_template(
  name: 'security/ssh',
  state_type: :state,
  category: 'security',
  description: 'SSH hardening - disable root login, password auth, and configure secure settings',
  content: <<~YAML
    # SSH Hardening
    # Disables root login, password authentication, and applies security best practices

    openssh-server:
      pkg.installed: []

    # SSH configuration
    sshd_config:
      file.managed:
        - name: /etc/ssh/sshd_config
        - contents: |
            # Veracity Managed SSH Configuration
            Port {{ pillar.get('ssh:port', 22) }}
            Protocol 2

            # Authentication
            PermitRootLogin {{ pillar.get('ssh:permit_root', 'no') }}
            PasswordAuthentication {{ pillar.get('ssh:password_auth', 'no') }}
            PubkeyAuthentication yes
            PermitEmptyPasswords no
            ChallengeResponseAuthentication no
            UsePAM yes

            # Security
            X11Forwarding no
            MaxAuthTries 3
            MaxSessions 10
            ClientAliveInterval 300
            ClientAliveCountMax 2

            # Subsystems
            Subsystem sftp /usr/lib/openssh/sftp-server

            # Allowed users (optional)
            {% if pillar.get('ssh:allowed_users') %}
            AllowUsers {{ pillar.get('ssh:allowed_users') | join(' ') }}
            {% endif %}
        - user: root
        - group: root
        - mode: 600
        - require:
          - pkg: openssh-server

    sshd:
      service.running:
        - name: sshd
        - enable: True
        - watch:
          - file: sshd_config
  YAML
)

seed_template(
  name: 'security/firewall',
  state_type: :state,
  category: 'security',
  description: 'UFW firewall configuration with sensible defaults',
  content: <<~YAML
    # UFW Firewall
    # Installs and configures UFW with common rules

    ufw:
      pkg.installed: []

    # Enable UFW
    ufw_enable:
      cmd.run:
        - name: ufw --force enable
        - unless: ufw status | grep -q "Status: active"
        - require:
          - pkg: ufw

    # Default policies
    ufw_default_incoming:
      cmd.run:
        - name: ufw default deny incoming
        - require:
          - cmd: ufw_enable

    ufw_default_outgoing:
      cmd.run:
        - name: ufw default allow outgoing
        - require:
          - cmd: ufw_enable

    # Allow SSH
    ufw_ssh:
      cmd.run:
        - name: ufw allow {{ pillar.get('ssh:port', 22) }}/tcp comment 'SSH'
        - unless: ufw status | grep -q "{{ pillar.get('ssh:port', 22) }}/tcp"
        - require:
          - cmd: ufw_enable

    # Allow HTTP/HTTPS (if web server)
    {% if pillar.get('firewall:allow_web', False) %}
    ufw_http:
      cmd.run:
        - name: ufw allow 80/tcp comment 'HTTP'
        - unless: ufw status | grep -q "80/tcp"

    ufw_https:
      cmd.run:
        - name: ufw allow 443/tcp comment 'HTTPS'
        - unless: ufw status | grep -q "443/tcp"
    {% endif %}

    # Custom ports from pillar
    {% for port in pillar.get('firewall:allow_ports', []) %}
    ufw_port_{{ port.port }}:
      cmd.run:
        - name: ufw allow {{ port.port }}/{{ port.get('proto', 'tcp') }} comment '{{ port.get('comment', 'Custom') }}'
        - unless: ufw status | grep -q "{{ port.port }}/{{ port.get('proto', 'tcp') }}"
    {% endfor %}
  YAML
)

seed_template(
  name: 'security/fail2ban',
  state_type: :state,
  category: 'security',
  description: 'Fail2ban intrusion prevention with SSH jail',
  content: <<~YAML
    # Fail2ban
    # Protects against brute-force attacks

    fail2ban:
      pkg.installed: []
      service.running:
        - enable: True
        - require:
          - pkg: fail2ban

    # SSH jail configuration
    /etc/fail2ban/jail.local:
      file.managed:
        - contents: |
            [DEFAULT]
            bantime = {{ pillar.get('fail2ban:bantime', '1h') }}
            findtime = {{ pillar.get('fail2ban:findtime', '10m') }}
            maxretry = {{ pillar.get('fail2ban:maxretry', 5) }}

            [sshd]
            enabled = true
            port = {{ pillar.get('ssh:port', 22) }}
            filter = sshd
            logpath = /var/log/auth.log
            maxretry = 3
            bantime = 1h
        - require:
          - pkg: fail2ban
        - watch_in:
          - service: fail2ban
  YAML
)

# =============================================================================
# Web Server States
# =============================================================================

seed_template(
  name: 'webserver/nginx',
  state_type: :state,
  category: 'web',
  description: 'Nginx web server with basic configuration',
  content: <<~YAML
    # Nginx Web Server
    # Installs and configures Nginx

    nginx:
      pkg.installed: []
      service.running:
        - enable: True
        - require:
          - pkg: nginx

    # Main configuration
    /etc/nginx/nginx.conf:
      file.managed:
        - contents: |
            user www-data;
            worker_processes auto;
            pid /run/nginx.pid;
            include /etc/nginx/modules-enabled/*.conf;

            events {
                worker_connections 1024;
                multi_accept on;
            }

            http {
                # Basic Settings
                sendfile on;
                tcp_nopush on;
                tcp_nodelay on;
                keepalive_timeout 65;
                types_hash_max_size 2048;
                server_tokens off;

                include /etc/nginx/mime.types;
                default_type application/octet-stream;

                # Logging
                access_log /var/log/nginx/access.log;
                error_log /var/log/nginx/error.log;

                # Gzip
                gzip on;
                gzip_vary on;
                gzip_proxied any;
                gzip_comp_level 6;
                gzip_types text/plain text/css text/xml application/json application/javascript application/xml;

                # Virtual Hosts
                include /etc/nginx/conf.d/*.conf;
                include /etc/nginx/sites-enabled/*;
            }
        - watch_in:
          - service: nginx

    # Create directories
    /etc/nginx/sites-available:
      file.directory:
        - mode: 755

    /etc/nginx/sites-enabled:
      file.directory:
        - mode: 755

    # Default site
    /etc/nginx/sites-available/default:
      file.managed:
        - contents: |
            server {
                listen 80 default_server;
                listen [::]:80 default_server;

                root /var/www/html;
                index index.html index.htm;

                server_name _;

                location / {
                    try_files $uri $uri/ =404;
                }
            }
        - require:
          - file: /etc/nginx/sites-available
        - watch_in:
          - service: nginx
  YAML
)

seed_template(
  name: 'webserver/certbot',
  state_type: :state,
  category: 'web',
  description: 'Let\'s Encrypt SSL certificates with Certbot',
  content: <<~YAML
    # Certbot (Let's Encrypt)
    # Automatic SSL certificate management

    certbot:
      pkg.installed:
        - pkgs:
          - certbot
          - python3-certbot-nginx

    # Auto-renewal timer
    certbot_renewal_timer:
      service.running:
        - name: certbot.timer
        - enable: True
        - require:
          - pkg: certbot

    # Obtain certificate for domains (manual trigger)
    {% if pillar.get('certbot:domains') %}
    {% for domain in pillar.get('certbot:domains', []) %}
    certbot_{{ domain | replace('.', '_') }}:
      cmd.run:
        - name: certbot certonly --nginx -d {{ domain }} --non-interactive --agree-tos --email {{ pillar.get('certbot:email', 'admin@example.com') }}
        - unless: test -d /etc/letsencrypt/live/{{ domain }}
        - require:
          - pkg: certbot
    {% endfor %}
    {% endif %}
  YAML
)

# =============================================================================
# Docker States
# =============================================================================

seed_template(
  name: 'docker/init',
  state_type: :state,
  category: 'docker',
  description: 'Docker CE installation with Docker Compose',
  content: <<~YAML
    # Docker Installation
    # Installs Docker CE and Docker Compose on Debian/Ubuntu

    {% if grains['os_family'] == 'Debian' %}

    # Prerequisites
    docker_prereqs:
      pkg.installed:
        - pkgs:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release

    # Add Docker GPG key
    docker_gpg:
      cmd.run:
        - name: |
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/{{ grains['os']|lower }}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        - creates: /etc/apt/keyrings/docker.gpg
        - require:
          - pkg: docker_prereqs

    # Add Docker repository
    docker_repo:
      pkgrepo.managed:
        - humanname: Docker Repository
        - name: deb [arch={{ grains['osarch'] }} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
        - file: /etc/apt/sources.list.d/docker.list
        - require:
          - cmd: docker_gpg

    # Install Docker packages
    docker_packages:
      pkg.installed:
        - pkgs:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-buildx-plugin
          - docker-compose-plugin
        - require:
          - pkgrepo: docker_repo

    docker:
      service.running:
        - enable: True
        - require:
          - pkg: docker_packages

    # Add users to docker group
    {% for user in pillar.get('docker:users', []) %}
    docker_group_{{ user }}:
      group.present:
        - name: docker
        - addusers:
          - {{ user }}
        - require:
          - service: docker
    {% endfor %}

    {% endif %}
  YAML
)

# =============================================================================
# Database States
# =============================================================================

seed_template(
  name: 'database/postgresql',
  state_type: :state,
  category: 'database',
  description: 'PostgreSQL server with database and user creation',
  content: <<~YAML
    # PostgreSQL
    # Installs and configures PostgreSQL with databases from pillar

    postgresql:
      pkg.installed:
        - name: postgresql
      service.running:
        - name: postgresql
        - enable: True
        - require:
          - pkg: postgresql

    # Create databases from pillar
    {% for db_name, db_config in pillar.get('postgresql:databases', {}).items() %}
    {{ db_name }}_database:
      postgres_database.present:
        - name: {{ db_name }}
        - owner: {{ db_config.get('owner', 'postgres') }}
        - require:
          - service: postgresql

    {% if db_config.get('user') %}
    {{ db_name }}_user:
      postgres_user.present:
        - name: {{ db_config.get('user') }}
        - password: {{ db_config.get('password', 'changeme') }}
        - login: True
        - require:
          - service: postgresql
    {% endif %}
    {% endfor %}

    # Configure pg_hba.conf for remote access if enabled
    {% if pillar.get('postgresql:allow_remote', False) %}
    pg_hba_remote:
      file.append:
        - name: /etc/postgresql/{{ pillar.get('postgresql:version', '14') }}/main/pg_hba.conf
        - text: |
            # Allow remote connections
            host    all             all             0.0.0.0/0               md5
        - require:
          - pkg: postgresql
        - watch_in:
          - service: postgresql
    {% endif %}
  YAML
)

# =============================================================================
# Monitoring States
# =============================================================================

seed_template(
  name: 'monitoring/node-exporter',
  state_type: :state,
  category: 'monitoring',
  description: 'Prometheus Node Exporter for system metrics',
  content: <<~YAML
    # Prometheus Node Exporter
    # Exports system metrics for Prometheus

    prometheus-node-exporter:
      pkg.installed: []
      service.running:
        - enable: True
        - require:
          - pkg: prometheus-node-exporter

    # Open port 9100 if firewall is managed
    {% if pillar.get('firewall:managed', False) %}
    node_exporter_firewall:
      cmd.run:
        - name: ufw allow from {{ pillar.get('monitoring:prometheus_server', '127.0.0.1') }} to any port 9100 proto tcp
        - unless: ufw status | grep -q "9100"
    {% endif %}
  YAML
)

# =============================================================================
# Cloud Profiles
# =============================================================================

seed_template(
  name: 'hetzner-cx11',
  state_type: :cloud_profile,
  category: 'cloud',
  description: 'Hetzner Cloud CX11 - 1 vCPU, 2GB RAM, 20GB SSD',
  content: <<~YAML
    # Hetzner Cloud - CX11 Profile
    # Entry-level shared vCPU instance

    hetzner-cx11:
      provider: hetzner-cloud
      size: cx11
      image: ubuntu-22.04
      location: {{ pillar.get('hetzner:default_location', 'fsn1') }}
      ssh_username: root
      ssh_key_file: {{ pillar.get('hetzner:ssh_key_file', '/root/.ssh/id_ed25519') }}
      ssh_key_names:
        - {{ pillar.get('hetzner:ssh_key_name', 'salt-master') }}
      minion:
        master: {{ pillar.get('salt:master_ip') }}
  YAML
)

seed_template(
  name: 'hetzner-cx21',
  state_type: :cloud_profile,
  category: 'cloud',
  description: 'Hetzner Cloud CX21 - 2 vCPU, 4GB RAM, 40GB SSD',
  content: <<~YAML
    # Hetzner Cloud - CX21 Profile
    # Standard shared vCPU instance

    hetzner-cx21:
      provider: hetzner-cloud
      size: cx21
      image: ubuntu-22.04
      location: {{ pillar.get('hetzner:default_location', 'fsn1') }}
      ssh_username: root
      ssh_key_file: {{ pillar.get('hetzner:ssh_key_file', '/root/.ssh/id_ed25519') }}
      ssh_key_names:
        - {{ pillar.get('hetzner:ssh_key_name', 'salt-master') }}
      minion:
        master: {{ pillar.get('salt:master_ip') }}
  YAML
)

seed_template(
  name: 'hetzner-cx31',
  state_type: :cloud_profile,
  category: 'cloud',
  description: 'Hetzner Cloud CX31 - 2 vCPU, 8GB RAM, 80GB SSD',
  content: <<~YAML
    # Hetzner Cloud - CX31 Profile
    # Enhanced shared vCPU instance with more RAM

    hetzner-cx31:
      provider: hetzner-cloud
      size: cx31
      image: ubuntu-22.04
      location: {{ pillar.get('hetzner:default_location', 'fsn1') }}
      ssh_username: root
      ssh_key_file: {{ pillar.get('hetzner:ssh_key_file', '/root/.ssh/id_ed25519') }}
      ssh_key_names:
        - {{ pillar.get('hetzner:ssh_key_name', 'salt-master') }}
      minion:
        master: {{ pillar.get('salt:master_ip') }}
  YAML
)

# =============================================================================
# Orchestration States
# =============================================================================

seed_template(
  name: 'deploy-webserver',
  state_type: :orchestration,
  category: 'orchestration',
  description: 'Full webserver deployment orchestration - base, security, nginx, SSL',
  content: <<~YAML
    # Webserver Deployment Orchestration
    # Multi-step deployment: base -> security -> nginx -> SSL

    # Step 1: Apply base configuration
    apply_base:
      salt.state:
        - tgt: {{ pillar['target'] }}
        - sls:
          - base/init
        - pillar: {{ pillar | json }}

    # Step 2: Apply security hardening
    apply_security:
      salt.state:
        - tgt: {{ pillar['target'] }}
        - sls:
          - security/ssh
          - security/firewall
          - security/fail2ban
        - pillar:
            firewall:
              allow_web: True
        - require:
          - salt: apply_base

    # Step 3: Install Nginx
    apply_nginx:
      salt.state:
        - tgt: {{ pillar['target'] }}
        - sls:
          - webserver/nginx
        - require:
          - salt: apply_security

    # Step 4: Configure SSL (optional)
    {% if pillar.get('ssl:enabled', False) %}
    apply_ssl:
      salt.state:
        - tgt: {{ pillar['target'] }}
        - sls:
          - webserver/certbot
        - pillar:
            certbot:
              domains: {{ pillar.get('ssl:domains', []) | json }}
              email: {{ pillar.get('ssl:email', 'admin@example.com') }}
        - require:
          - salt: apply_nginx
    {% endif %}

    # Step 5: Verify deployment
    verify_nginx:
      salt.function:
        - name: cmd.run
        - tgt: {{ pillar['target'] }}
        - arg:
          - 'systemctl is-active nginx && curl -s -o /dev/null -w "%{http_code}" http://localhost'
        - require:
          - salt: apply_nginx
  YAML
)

seed_template(
  name: 'provision-hetzner-vm',
  state_type: :orchestration,
  category: 'orchestration',
  description: 'Provision new Hetzner VM and apply initial configuration',
  content: <<~YAML
    # Hetzner VM Provisioning Orchestration
    # Creates a new VM and applies initial configuration

    # Step 1: Provision the VM
    provision_vm:
      salt.function:
        - name: cloud.profile
        - tgt: salt-master
        - tgt_type: list
        - arg:
          - {{ pillar.get('profile', 'hetzner-cx21') }}
          - {{ pillar['vm_name'] }}
        - kwarg:
            parallel: True

    # Step 2: Wait for minion to connect
    wait_for_minion:
      salt.wait_for_event:
        - name: salt/minion/{{ pillar['vm_name'] }}/start
        - id_list:
          - {{ pillar['vm_name'] }}
        - timeout: 300
        - require:
          - salt: provision_vm

    # Step 3: Accept the minion key
    accept_key:
      salt.wheel:
        - name: key.accept
        - match: {{ pillar['vm_name'] }}
        - require:
          - salt: wait_for_minion

    # Step 4: Sync modules
    sync_all:
      salt.function:
        - name: saltutil.sync_all
        - tgt: {{ pillar['vm_name'] }}
        - require:
          - salt: accept_key

    # Step 5: Apply initial configuration
    {% for state in pillar.get('apply_states', ['base/init']) %}
    apply_{{ state | replace('/', '_') }}:
      salt.state:
        - tgt: {{ pillar['vm_name'] }}
        - sls:
          - {{ state }}
        - require:
          - salt: sync_all
          {% if not loop.first %}
          - salt: apply_{{ pillar.get('apply_states', ['base/init'])[loop.index0 - 1] | replace('/', '_') }}
          {% endif %}
    {% endfor %}

    # Step 6: Return VM information
    get_vm_info:
      salt.function:
        - name: grains.items
        - tgt: {{ pillar['vm_name'] }}
        - require:
          - salt: apply_{{ pillar.get('apply_states', ['base/init'])[-1] | replace('/', '_') }}
  YAML
)

puts ""
puts "Salt Templates seeded successfully!"
puts "  Total templates: #{SaltState.templates.count}"
puts ""
puts "Categories:"
SaltState.templates.group(:category).count.each do |category, count|
  puts "  #{category || 'uncategorized'}: #{count}"
end
