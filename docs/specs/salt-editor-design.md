# Salt Editor & Orchestration - Design Document

## Overview

Add a comprehensive Salt management interface to Veracity that allows users to:
1. **Create and edit Salt States** - Configuration management files
2. **Manage Salt Cloud Profiles** - VM provisioning templates for Hetzner, etc.
3. **Build Orchestration Workflows** - Multi-step deployment pipelines
4. **Use Pre-built Templates** - Common configurations with one click

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Veracity Salt Editor                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐ │
│  │   States    │   │   Cloud     │   │ Orchestrate │   │  Templates  │ │
│  │   Editor    │   │  Profiles   │   │   Runner    │   │   Library   │ │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘ │
│         │                 │                 │                 │         │
│         └────────────────┬┴─────────────────┴─────────────────┘         │
│                          │                                               │
│                   ┌──────▼──────┐                                       │
│                   │   Monaco    │  (Code Editor with YAML syntax)       │
│                   │   Editor    │                                       │
│                   └──────┬──────┘                                       │
│                          │                                               │
├──────────────────────────┼──────────────────────────────────────────────┤
│                          │                                               │
│                   ┌──────▼──────┐                                       │
│                   │  Database   │                                       │
│                   │  (States)   │                                       │
│                   └──────┬──────┘                                       │
│                          │                                               │
│                   ┌──────▼──────┐                                       │
│                   │  Salt       │  (Deploy to /srv/salt, /srv/pillar)   │
│                   │  Master     │                                       │
│                   └─────────────┘                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Database Models

### 1. SaltState (States & Pillar)

```ruby
# app/models/salt_state.rb
class SaltState < ApplicationRecord
  # Types: state, pillar, orchestration, cloud_profile, cloud_provider, map
  enum :state_type, {
    state: 0,           # /srv/salt/*.sls
    pillar: 1,          # /srv/pillar/*.sls
    orchestration: 2,   # /srv/salt/orch/*.sls
    cloud_profile: 3,   # /etc/salt/cloud.profiles.d/*.conf
    cloud_provider: 4,  # /etc/salt/cloud.providers.d/*.conf
    cloud_map: 5        # /etc/salt/cloud.maps.d/*.map
  }

  # Fields:
  # - name: string (e.g., "webserver", "nginx", "hetzner-cx21")
  # - state_type: integer (enum above)
  # - content: text (YAML content)
  # - description: text
  # - category: string (e.g., "web", "database", "security", "cloud")
  # - is_template: boolean (pre-built example vs user-created)
  # - is_active: boolean (deployed to Salt master)
  # - file_path: string (computed path on Salt master)
  # - last_deployed_at: datetime
  # - created_by_id: references user
end
```

### 2. SaltExecution (Run history)

```ruby
# app/models/salt_execution.rb
class SaltExecution < ApplicationRecord
  belongs_to :salt_state, optional: true
  belongs_to :user

  # Fields:
  # - execution_type: string (highstate, state.apply, orchestrate, cloud.profile)
  # - target: string (minion pattern or VM name)
  # - status: string (pending, running, completed, failed)
  # - output: text (Salt output)
  # - started_at: datetime
  # - completed_at: datetime
end
```

---

## File Organization on Salt Master

```
/srv/salt/                          # States (file_roots)
├── top.sls                         # Auto-generated from DB
├── base/
│   ├── init.sls                    # Base system config
│   ├── packages.sls
│   └── users.sls
├── security/
│   ├── init.sls
│   ├── firewall.sls
│   └── ssh.sls
├── webserver/
│   ├── init.sls
│   ├── nginx.sls
│   └── apache.sls
├── database/
│   ├── init.sls
│   ├── postgresql.sls
│   └── mysql.sls
├── docker/
│   └── init.sls
└── orch/                           # Orchestration states
    ├── deploy_webserver.sls
    └── provision_hetzner.sls

/srv/pillar/                        # Pillar data
├── top.sls                         # Auto-generated
├── common.sls
└── minions/                        # Per-minion secrets
    └── {minion_id}/
        └── secrets.sls

/etc/salt/cloud.providers.d/        # Cloud providers
├── hetzner.conf
└── digitalocean.conf

/etc/salt/cloud.profiles.d/         # Cloud profiles
├── hetzner-small.conf
├── hetzner-medium.conf
└── hetzner-large.conf

/etc/salt/cloud.maps.d/             # Cloud maps
└── production.map
```

---

## Pre-built Templates Library

### Category: Base System

```yaml
# base/init.sls - Base System Configuration
{% set timezone = pillar.get('system:timezone', 'UTC') %}

# Set timezone
timezone:
  timezone.system:
    - name: {{ timezone }}

# Install base packages
base_packages:
  pkg.installed:
    - pkgs:
      - curl
      - wget
      - vim
      - htop
      - git
      - unzip

# Configure automatic updates
{% if grains['os_family'] == 'Debian' %}
unattended-upgrades:
  pkg.installed: []

/etc/apt/apt.conf.d/20auto-upgrades:
  file.managed:
    - contents: |
        APT::Periodic::Update-Package-Lists "1";
        APT::Periodic::Unattended-Upgrade "1";
{% endif %}
```

### Category: Security

```yaml
# security/ssh.sls - SSH Hardening
sshd_config:
  file.managed:
    - name: /etc/ssh/sshd_config
    - source: salt://security/files/sshd_config
    - user: root
    - group: root
    - mode: 600

sshd:
  service.running:
    - enable: True
    - watch:
      - file: sshd_config

# Disable root login
disable_root_ssh:
  file.replace:
    - name: /etc/ssh/sshd_config
    - pattern: '^#?PermitRootLogin.*'
    - repl: 'PermitRootLogin no'
    - watch_in:
      - service: sshd
```

```yaml
# security/firewall.sls - UFW Firewall
ufw:
  pkg.installed: []

ufw_enable:
  cmd.run:
    - name: ufw --force enable
    - unless: ufw status | grep -q "Status: active"
    - require:
      - pkg: ufw

# Allow SSH
ufw_ssh:
  cmd.run:
    - name: ufw allow 22/tcp
    - unless: ufw status | grep -q "22/tcp"
    - require:
      - cmd: ufw_enable

# Allow HTTP/HTTPS (conditional)
{% if pillar.get('firewall:allow_web', False) %}
ufw_http:
  cmd.run:
    - name: ufw allow 80/tcp
    - unless: ufw status | grep -q "80/tcp"

ufw_https:
  cmd.run:
    - name: ufw allow 443/tcp
    - unless: ufw status | grep -q "443/tcp"
{% endif %}
```

### Category: Web Server

```yaml
# webserver/nginx.sls - Nginx Web Server
nginx:
  pkg.installed: []
  service.running:
    - enable: True
    - require:
      - pkg: nginx

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://webserver/files/nginx.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - watch_in:
      - service: nginx

# Create sites directory
/etc/nginx/sites-available:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/etc/nginx/sites-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
```

### Category: Docker

```yaml
# docker/init.sls - Docker Installation
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
    - name: curl -fsSL https://download.docker.com/linux/{{ grains['os']|lower }}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    - creates: /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
docker_repo:
  pkgrepo.managed:
    - humanname: Docker Repository
    - name: deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker.list
    - require:
      - cmd: docker_gpg

# Install Docker
docker-ce:
  pkg.installed:
    - require:
      - pkgrepo: docker_repo

docker:
  service.running:
    - enable: True
    - require:
      - pkg: docker-ce

# Install Docker Compose
docker-compose:
  pkg.installed:
    - name: docker-compose-plugin

{% endif %}
```

### Category: Database

```yaml
# database/postgresql.sls - PostgreSQL
postgresql:
  pkg.installed:
    - name: postgresql
  service.running:
    - name: postgresql
    - enable: True
    - require:
      - pkg: postgresql

# Create application database
{% if pillar.get('postgresql:database') %}
{{ pillar['postgresql']['database'] }}:
  postgres_database.present:
    - require:
      - service: postgresql

{{ pillar['postgresql']['user'] }}:
  postgres_user.present:
    - password: {{ pillar['postgresql']['password'] }}
    - require:
      - service: postgresql
{% endif %}
```

### Category: Cloud Profiles (Hetzner)

```yaml
# hetzner-small.conf - Hetzner CX11 Profile
hetzner-cx11:
  provider: hetzner-cloud
  size: cx11
  image: ubuntu-22.04
  location: fsn1
  ssh_username: root
  minion:
    master: {{ pillar['salt:master_ip'] }}

# hetzner-medium.conf - Hetzner CX21 Profile
hetzner-cx21:
  provider: hetzner-cloud
  size: cx21
  image: ubuntu-22.04
  location: fsn1
  ssh_username: root
  minion:
    master: {{ pillar['salt:master_ip'] }}

# hetzner-large.conf - Hetzner CX31 Profile
hetzner-cx31:
  provider: hetzner-cloud
  size: cx31
  image: ubuntu-22.04
  location: fsn1
  ssh_username: root
  minion:
    master: {{ pillar['salt:master_ip'] }}
```

### Category: Orchestration

```yaml
# orch/provision_webserver.sls - Full Webserver Deployment
# 1. Provision VM on Hetzner
provision_vm:
  salt.function:
    - name: cloud.profile
    - tgt: salt-master
    - arg:
      - hetzner-cx21
      - {{ pillar['vm_name'] }}
    - kwarg:
        parallel: True

# 2. Wait for minion to connect
wait_for_minion:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ pillar['vm_name'] }}
    - timeout: 300
    - require:
      - salt: provision_vm

# 3. Apply base configuration
apply_base:
  salt.state:
    - tgt: {{ pillar['vm_name'] }}
    - sls:
      - base
      - security
    - require:
      - salt: wait_for_minion

# 4. Apply webserver configuration
apply_webserver:
  salt.state:
    - tgt: {{ pillar['vm_name'] }}
    - sls:
      - webserver.nginx
    - require:
      - salt: apply_base

# 5. Verify deployment
verify:
  salt.function:
    - name: cmd.run
    - tgt: {{ pillar['vm_name'] }}
    - arg:
      - 'curl -s localhost | head -5'
    - require:
      - salt: apply_webserver
```

---

## UI Design

### Navigation

```
Administration
├── ...
├── Salt Editor          <-- NEW
│   ├── States           (browse/edit state files)
│   ├── Pillar           (manage pillar data)
│   ├── Cloud Profiles   (Hetzner, etc.)
│   ├── Orchestration    (deployment workflows)
│   ├── Templates        (pre-built examples)
│   └── Executions       (run history)
```

### States Editor Page

```
┌─────────────────────────────────────────────────────────────────────┐
│ Salt States                                           [+ New State] │
├─────────────────────────────────────────────────────────────────────┤
│ Categories: [All] [Base] [Security] [Web] [Database] [Docker]      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐        │
│ │ base/init.sls   │ │ security/ssh    │ │ webserver/nginx │        │
│ │ Base System     │ │ SSH Hardening   │ │ Nginx Server    │        │
│ │ ● Deployed      │ │ ● Deployed      │ │ ○ Not deployed  │        │
│ │ [Edit] [Deploy] │ │ [Edit] [Deploy] │ │ [Edit] [Deploy] │        │
│ └─────────────────┘ └─────────────────┘ └─────────────────┘        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Editor View (Monaco Editor)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Edit: webserver/nginx.sls                    [Save] [Deploy] [Test] │
├─────────────────────────────────────────────────────────────────────┤
│ ┌───────────────────────────────────────────────────────────────┐   │
│ │  1 │ # Nginx Web Server                                       │   │
│ │  2 │ nginx:                                                   │   │
│ │  3 │   pkg.installed: []                                      │   │
│ │  4 │   service.running:                                       │   │
│ │  5 │     - enable: True                                       │   │
│ │  6 │     - require:                                           │   │
│ │  7 │       - pkg: nginx                                       │   │
│ │  8 │                                                          │   │
│ │  9 │ /etc/nginx/nginx.conf:                                   │   │
│ │ 10 │   file.managed:                                          │   │
│ │ 11 │     - source: salt://webserver/files/nginx.conf          │   │
│ │ 12 │     - template: jinja                                    │   │
│ └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│ ┌─ Validation ──────────────────────────────────────────────────┐   │
│ │ ✓ YAML syntax valid                                           │   │
│ │ ✓ State IDs are unique                                        │   │
│ │ ⚠ Using 'pkg.installed' without version pinning               │   │
│ └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Cloud Profiles Page

```
┌─────────────────────────────────────────────────────────────────────┐
│ Cloud Profiles                                    [+ New Profile]   │
├─────────────────────────────────────────────────────────────────────┤
│ Provider: [All] [Hetzner] [DigitalOcean] [AWS]                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Hetzner Cloud                                                       │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐        │
│ │ hetzner-cx11    │ │ hetzner-cx21    │ │ hetzner-cx31    │        │
│ │ 1 vCPU, 2GB RAM │ │ 2 vCPU, 4GB RAM │ │ 2 vCPU, 8GB RAM │        │
│ │ Ubuntu 22.04    │ │ Ubuntu 22.04    │ │ Ubuntu 22.04    │        │
│ │ fsn1            │ │ fsn1            │ │ fsn1            │        │
│ │                 │ │                 │ │                 │        │
│ │ [Edit] [Clone]  │ │ [Edit] [Clone]  │ │ [Edit] [Clone]  │        │
│ │ [Provision VM]  │ │ [Provision VM]  │ │ [Provision VM]  │        │
│ └─────────────────┘ └─────────────────┘ └─────────────────┘        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Provision VM Modal

```
┌─────────────────────────────────────────────────────────────────────┐
│ Provision New VM                                              [X]   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Profile: hetzner-cx21                                               │
│                                                                      │
│ VM Name: [web-03_______________]                                    │
│                                                                      │
│ Location: [fsn1 (Frankfurt) ▼]                                      │
│                                                                      │
│ Apply States After Provisioning:                                    │
│ ☑ base        - Base system configuration                          │
│ ☑ security    - SSH hardening, firewall                            │
│ ☑ webserver   - Nginx web server                                   │
│ ☐ docker      - Docker & Docker Compose                            │
│ ☐ database    - PostgreSQL                                         │
│                                                                      │
│ Add to Group: [Production Servers ▼]                                │
│                                                                      │
│                                    [Cancel] [Provision & Configure] │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Services

### SaltEditorService

```ruby
# app/services/salt_editor_service.rb
class SaltEditorService
  SALT_FILE_ROOTS = '/srv/salt'
  PILLAR_ROOTS = '/srv/pillar'
  CLOUD_PROVIDERS_DIR = '/etc/salt/cloud.providers.d'
  CLOUD_PROFILES_DIR = '/etc/salt/cloud.profiles.d'
  CLOUD_MAPS_DIR = '/etc/salt/cloud.maps.d'

  class << self
    # Deploy a state to the Salt master
    def deploy_state(salt_state)
      path = compute_file_path(salt_state)
      write_to_salt_master(path, salt_state.content)
      salt_state.update!(is_active: true, last_deployed_at: Time.current)
    end

    # Validate YAML syntax
    def validate_yaml(content)
      YAML.safe_load(content)
      { valid: true }
    rescue Psych::SyntaxError => e
      { valid: false, error: e.message, line: e.line }
    end

    # Apply state to minions
    def apply_state(state_name, target)
      SaltService.run_command(target, 'state.apply', [state_name])
    end

    # Run orchestration
    def run_orchestration(orch_name, pillar_data = {})
      # salt-run state.orchestrate orch.{name} pillar='{...}'
    end

    private

    def compute_file_path(salt_state)
      case salt_state.state_type
      when 'state'
        "#{SALT_FILE_ROOTS}/#{salt_state.name}.sls"
      when 'pillar'
        "#{PILLAR_ROOTS}/#{salt_state.name}.sls"
      when 'orchestration'
        "#{SALT_FILE_ROOTS}/orch/#{salt_state.name}.sls"
      when 'cloud_profile'
        "#{CLOUD_PROFILES_DIR}/#{salt_state.name}.conf"
      when 'cloud_provider'
        "#{CLOUD_PROVIDERS_DIR}/#{salt_state.name}.conf"
      when 'cloud_map'
        "#{CLOUD_MAPS_DIR}/#{salt_state.name}.map"
      end
    end

    def write_to_salt_master(path, content)
      # Write file to Salt master via Salt API or direct file write
      File.write(path, content)
    end
  end
end
```

### SaltCloudService

```ruby
# app/services/salt_cloud_service.rb
class SaltCloudService
  class << self
    # Provision a new VM
    def provision_vm(profile_name, vm_name, options = {})
      # salt-cloud -p {profile} {vm_name} -y
      cmd = "salt-cloud -p #{profile_name} #{vm_name} -y --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # List available profiles
    def list_profiles
      cmd = "salt-cloud --list-profiles --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # List available images for a provider
    def list_images(provider)
      cmd = "salt-cloud -f avail_images #{provider} --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # List available sizes for a provider
    def list_sizes(provider)
      cmd = "salt-cloud -f avail_sizes #{provider} --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # List available locations for a provider
    def list_locations(provider)
      cmd = "salt-cloud -f avail_locations #{provider} --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # Destroy a VM
    def destroy_vm(vm_name)
      cmd = "salt-cloud -d #{vm_name} -y --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    # Query existing VMs
    def query_vms
      cmd = "salt-cloud -Q --out=json"
      result = execute_command(cmd)
      parse_result(result)
    end

    private

    def execute_command(cmd)
      # Execute on Salt master
      `#{cmd} 2>&1`
    end

    def parse_result(output)
      JSON.parse(output)
    rescue JSON::ParserError
      { success: false, error: output }
    end
  end
end
```

---

## Implementation Phases

### Phase 1: Core Editor (Week 1)
- [ ] Database migrations for SaltState model
- [ ] Basic CRUD controller for states
- [ ] Monaco editor integration
- [ ] YAML validation
- [ ] Deploy to Salt master functionality

### Phase 2: Templates Library (Week 2)
- [ ] Seed database with pre-built templates
- [ ] Template categories and browsing
- [ ] Clone template to create custom state
- [ ] Import/export functionality

### Phase 3: Cloud Integration (Week 3)
- [ ] Salt Cloud provider configuration
- [ ] Cloud profiles management
- [ ] VM provisioning workflow
- [ ] Integration with existing Hetzner API keys

### Phase 4: Orchestration (Week 4)
- [ ] Orchestration editor
- [ ] Workflow visualization
- [ ] Execution monitoring
- [ ] Logs and history

---

## Security Considerations

1. **File Permissions**: All Salt files written with proper ownership (root:root, 0644)
2. **Secrets**: API keys stored in pillar with encryption, never in states
3. **Validation**: All YAML validated before deployment
4. **RBAC**: Only admins can deploy states, operators can edit drafts
5. **Audit**: All state changes logged with user and timestamp

---

## Questions for Review

1. Should we use Monaco Editor (VS Code's editor) or CodeMirror for the code editor?
2. Should states be versioned (git-like history)?
3. Should we allow direct file editing on Salt master, or always go through DB?
4. How should we handle secrets in pillar data? (Vault integration?)
