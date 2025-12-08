# Tech Stack

## Framework and Runtime

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Application Framework** | Ruby on Rails | 8.1 | Full-stack web framework with convention over configuration |
| **Language** | Ruby | 3.3.6 | Server-side language for application logic |
| **Runtime Manager** | Mise | Latest | Ruby version management (replaces rbenv/rvm) |
| **Package Manager** | Bundler | 2.x | Ruby dependency management via Gemfile |
| **Asset Pipeline** | Propshaft | Latest | Rails 8 modern asset pipeline (replaces Sprockets) |
| **Web Server** | Puma | 6.x | Multi-threaded application server |
| **Reverse Proxy** | Caddy | Latest | Auto-HTTPS, reverse proxy to Puma |

## Frontend

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **JavaScript Framework** | Hotwire (Turbo + Stimulus) | 8.x | Modern Rails frontend without heavy JS frameworks |
| **CSS Framework** | Tailwind CSS | 4.x | Utility-first CSS framework |
| **UI Components** | DaisyUI | 5.x | Tailwind component library with themes |
| **Charts** | Chartkick + Chart.js | 5.x / 4.x | Dashboard charts and metrics visualization |
| **Real-time** | Turbo Streams | 8.x | WebSocket-based partial updates |
| **Build Tool** | esbuild | Latest | JavaScript bundling (via jsbundling-rails) |

## Database and Storage

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Primary Database** | PostgreSQL | 14+ | Relational data storage with UUID support |
| **ORM** | Active Record | 8.x | Rails database abstraction layer |
| **Cache** | Redis | 7+ | Application cache, Salt API token storage |
| **Job Queue Backend** | Redis | 7+ | Sidekiq job queue storage |
| **Session Store** | Database | - | Devise session storage via Active Record |
| **Encryption** | Active Record Encryption | 8.x | Column-level encryption for sensitive data |
| **Additional Encryption** | attr_encrypted | 4.x | Legacy encrypted attributes (API tokens) |

## Background Processing

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Job Framework** | Sidekiq | 7.x | Background job processing with Redis |
| **Scheduler** | sidekiq-cron | 1.x | Cron-based recurring job scheduling |
| **Solid Queue** | solid_queue | Latest | Rails 8 database-backed queue (alternative to Sidekiq) |
| **Solid Cache** | solid_cache | Latest | Rails 8 database-backed cache |
| **Solid Cable** | solid_cable | Latest | Rails 8 database-backed Action Cable |

## Authentication and Authorization

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Authentication** | Devise | 4.9 | User authentication with sessions, passwords, confirmations |
| **2FA/TOTP** | ROTP | 6.x | Time-based one-time password generation |
| **QR Codes** | rqrcode | 2.x | QR code generation for 2FA setup |
| **OAuth** | OmniAuth | 2.x | OAuth2 provider integration |
| **Authorization** | Pundit | 2.x | Policy-based authorization (Admin/Operator/Viewer roles) |
| **Rate Limiting** | Rack::Attack | 6.x | Request throttling and IP blocking |

## Real-time Features

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **WebSockets** | Action Cable | 8.x | Real-time bidirectional communication |
| **Broadcasting** | Turbo Streams | 8.x | Server-to-client partial updates |
| **Dashboard Updates** | DashboardChannel | - | Live server status and metrics updates |
| **Command Output** | SaltCliChannel | - | Real-time Salt command output streaming |

## Infrastructure Automation

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Configuration Management** | SaltStack | 3007 | Server orchestration, state management, command execution |
| **Salt API** | CherryPy REST | 3007 | HTTP API for Salt Master communication |
| **Salt Authentication** | PAM | - | System user authentication for Salt API |
| **Salt Events** | EventMachine | 1.x | Salt event stream subscription |
| **HTTP Client** | HTTParty | 0.21 | Salt API and external service communication |

## Cloud Integrations

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Hetzner Cloud** | Python hcloud library | Server management, snapshots via lib/scripts/hetzner_cloud.py |
| **Proxmox VE** | Python proxmoxer library | VM/LXC control, snapshots via lib/scripts/proxmox_api.py |
| **CVE Monitoring** | Python PyVulnerabilityLookup | CVE data from vulnerability.circl.lu |
| **Push Notifications** | Gotify API | Alert delivery via self-hosted Gotify server |
| **VPN** | NetBird | Zero-trust networking via Salt state deployment |

## Python Integrations

| Component | Location | Purpose |
|-----------|----------|---------|
| **Virtual Environment** | /opt/veracity/app/integrations_venv | Isolated Python environment for integrations |
| **Hetzner Script** | lib/scripts/hetzner_cloud.py | Hetzner Cloud API wrapper |
| **Proxmox Script** | lib/scripts/proxmox_api.py | Proxmox VE API wrapper with secure env var support |
| **CVE Service** | app/services/cve_monitoring_service.rb | Embedded Python for PyVulnerabilityLookup |

## Testing and Quality

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Test Framework** | Minitest | Rails default | Unit and integration testing |
| **System Tests** | Capybara + Selenium | Latest | Browser-based system testing |
| **Factories** | factory_bot_rails | 6.x | Test data generation |
| **Fake Data** | Faker | 3.x | Realistic test data |
| **HTTP Mocking** | WebMock | 3.x | External API request stubbing |
| **Mocking** | Mocha | 2.x | Object mocking and stubbing |
| **Coverage** | SimpleCov | 0.22 | Code coverage reporting |
| **Matchers** | shoulda-matchers | 6.x | Expressive test assertions |
| **Linting** | RuboCop | Rails Omakase | Ruby style enforcement |
| **Security** | Brakeman | Latest | Static security analysis |

## Deployment and Infrastructure

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Process Manager** | systemd | Application and Sidekiq service management |
| **Web Server** | Caddy | Auto-HTTPS reverse proxy |
| **Container Deploy** | Kamal | Docker-based deployment (optional) |
| **HTTP Acceleration** | Thruster | Puma HTTP caching/compression |
| **Version Manager** | Mise | Ruby and Node.js version management |

## Supported Operating Systems

| OS | Versions | Notes |
|----|----------|-------|
| **Ubuntu** | 20.04, 22.04, 24.04 LTS | Primary development and production target |
| **Debian** | 11 (Bullseye), 12 (Bookworm) | Fully supported |
| **Rocky Linux** | 8, 9 | Planned support |
| **AlmaLinux** | 8, 9 | Planned support |

## External Services

| Service | Purpose | Configuration |
|---------|---------|---------------|
| **Salt Master** | Infrastructure orchestration | Local, port 4505/4506 |
| **Salt API** | HTTP interface to Salt | Local, port 8001 |
| **PostgreSQL** | Primary database | Local or remote |
| **Redis** | Cache and job queue | Local, port 6379 |
| **Gotify** | Push notifications | Self-hosted, configurable URL |
| **Vulnerability Lookup** | CVE data | vulnerability.circl.lu (default) |

## Security Considerations

| Area | Implementation |
|------|----------------|
| **Secrets Storage** | Rails encrypted credentials (config/credentials.yml.enc) |
| **API Token Encryption** | attr_encrypted with AES-256-GCM |
| **Salt Credentials** | PAM authentication, never stored in application |
| **Proxmox Tokens** | Salt pillar-based delivery (never in command line) |
| **Session Security** | Secure cookies, CSRF protection, session timeout |
| **Input Validation** | Strong parameters, model validations |
| **SQL Injection** | Active Record parameterized queries |
| **XSS Prevention** | Rails automatic escaping, CSP headers |
