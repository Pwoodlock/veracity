# frozen_string_literal: true

class SaltState < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: 'User', optional: true

  # Enums for state types
  enum :state_type, {
    state: 0,           # /srv/salt/*.sls
    pillar: 1,          # /srv/pillar/*.sls
    orchestration: 2,   # /srv/salt/orch/*.sls
    cloud_profile: 3,   # /etc/salt/cloud.profiles.d/*.conf
    cloud_provider: 4,  # /etc/salt/cloud.providers.d/*.conf
    cloud_map: 5        # /etc/salt/cloud.maps.d/*.map
  }

  # Categories for organization
  CATEGORIES = %w[base security web database docker monitoring cloud orchestration other].freeze

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z0-9_\/-]+\z/i, message: 'only allows alphanumeric, underscore, hyphen, and forward slash' },
                   uniqueness: { scope: :state_type, case_sensitive: false }
  validates :state_type, presence: true
  validates :content, presence: true
  validates :category, inclusion: { in: CATEGORIES, allow_blank: true }

  # Scopes
  scope :templates, -> { where(is_template: true) }
  scope :user_created, -> { where(is_template: false) }
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :ordered, -> { order(:category, :name) }

  # Scopes by state type
  scope :states, -> { where(state_type: :state) }
  scope :pillars, -> { where(state_type: :pillar) }
  scope :orchestrations, -> { where(state_type: :orchestration) }
  scope :cloud_profiles, -> { where(state_type: :cloud_profile) }
  scope :cloud_providers, -> { where(state_type: :cloud_provider) }
  scope :cloud_maps, -> { where(state_type: :cloud_map) }

  # Callbacks
  before_save :compute_file_path

  # File paths on Salt master
  SALT_FILE_ROOTS = '/srv/salt'
  PILLAR_ROOTS = '/srv/pillar'
  CLOUD_PROVIDERS_DIR = '/etc/salt/cloud.providers.d'
  CLOUD_PROFILES_DIR = '/etc/salt/cloud.profiles.d'
  CLOUD_MAPS_DIR = '/etc/salt/cloud.maps.d'

  # Compute the file path on the Salt master
  def compute_file_path
    self.file_path = case state_type
                     when 'state'
                       "#{SALT_FILE_ROOTS}/#{name}.sls"
                     when 'pillar'
                       "#{PILLAR_ROOTS}/#{name}.sls"
                     when 'orchestration'
                       "#{SALT_FILE_ROOTS}/orch/#{name}.sls"
                     when 'cloud_profile'
                       "#{CLOUD_PROFILES_DIR}/#{name}.conf"
                     when 'cloud_provider'
                       "#{CLOUD_PROVIDERS_DIR}/#{name}.conf"
                     when 'cloud_map'
                       "#{CLOUD_MAPS_DIR}/#{name}.map"
                     else
                       "#{SALT_FILE_ROOTS}/#{name}.sls"
                     end
  end

  # File extension based on type
  def file_extension
    case state_type
    when 'cloud_profile', 'cloud_provider'
      '.conf'
    when 'cloud_map'
      '.map'
    else
      '.sls'
    end
  end

  # Validate YAML syntax
  def valid_yaml?
    return true if cloud_profile? || cloud_provider? # These may not be pure YAML

    YAML.safe_load(content, permitted_classes: [Symbol, Date, Time])
    true
  rescue Psych::SyntaxError
    false
  end

  # Get YAML validation error if any
  def yaml_error
    return nil if cloud_profile? || cloud_provider?

    YAML.safe_load(content, permitted_classes: [Symbol, Date, Time])
    nil
  rescue Psych::SyntaxError => e
    { line: e.line, column: e.column, message: e.message }
  end

  # Mark as deployed
  def mark_deployed!
    update!(is_active: true, last_deployed_at: Time.current)
  end

  # Mark as inactive (removed from Salt master)
  def mark_inactive!
    update!(is_active: false)
  end

  # Clone this state as a new user-created state
  def clone_as(new_name, user = nil)
    SaltState.new(
      name: new_name,
      state_type: state_type,
      content: content,
      description: description,
      category: category,
      is_template: false,
      is_active: false,
      created_by: user
    )
  end

  # Display name with type badge
  def display_name
    "#{name}#{file_extension}"
  end

  # Icon for state type
  def type_icon
    case state_type
    when 'state'
      'file-text'
    when 'pillar'
      'lock'
    when 'orchestration'
      'git-branch'
    when 'cloud_profile'
      'cloud'
    when 'cloud_provider'
      'server'
    when 'cloud_map'
      'map'
    else
      'file'
    end
  end

  # Badge color for state type
  def type_badge_class
    case state_type
    when 'state'
      'badge-primary'
    when 'pillar'
      'badge-warning'
    when 'orchestration'
      'badge-info'
    when 'cloud_profile'
      'badge-success'
    when 'cloud_provider'
      'badge-secondary'
    when 'cloud_map'
      'badge-accent'
    else
      'badge-ghost'
    end
  end
end
