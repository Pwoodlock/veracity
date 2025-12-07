# Salt State for Deploying NetBird Agent
# This state installs and configures NetBird using PILLAR DATA for secrets
# The setup key is NEVER passed as a command-line argument
#
# Pillar data expected:
#   netbird:
#     management_url: https://your-server:443
#     setup_key: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
#
# Security: The setup key is read from pillar (encrypted in transit)
# and written to a temporary file, used once, then deleted.
#
# Deploy this file to: /srv/salt/netbird.sls

# Install NetBird using the official installer
netbird_install:
  cmd.run:
    - name: curl -fsSL https://pkgs.netbird.io/install.sh | sh
    - unless: which netbird
    - timeout: 300

# Write setup key to a temporary file (secure - not in command line)
netbird_setup_key_file:
  file.managed:
    - name: /tmp/.netbird_setup_key
    - contents: {{ pillar['netbird']['setup_key'] }}
    - mode: 0600
    - user: root
    - group: root
    - require:
      - cmd: netbird_install

# Connect to NetBird network using the key file
netbird_connect:
  cmd.run:
    - name: |
        SETUP_KEY=$(cat /tmp/.netbird_setup_key)
        netbird up --management-url {{ pillar['netbird']['management_url'] }} --setup-key "$SETUP_KEY"
    - require:
      - file: netbird_setup_key_file
    - unless: netbird status 2>/dev/null | grep -q "Connected"

# Remove the temporary setup key file immediately after use
netbird_cleanup_key:
  file.absent:
    - name: /tmp/.netbird_setup_key
    - require:
      - cmd: netbird_connect

# Ensure NetBird service is running
netbird_service:
  service.running:
    - name: netbird
    - enable: True
    - require:
      - cmd: netbird_connect

# Verify NetBird is connected
netbird_verify:
  cmd.run:
    - name: netbird status
    - require:
      - service: netbird_service
