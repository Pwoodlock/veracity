# frozen_string_literal: true

# Groups allow organizing servers by company, project, or any logical grouping
class Group < ApplicationRecord
  # Associations
  has_many :servers, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color (e.g., #3B82F6)" }, allow_blank: true

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  after_save :update_servers_count
  # Note: No after_destroy callback needed - record is being deleted anyway

  # Scopes
  scope :ordered, -> { order(:name) }
  scope :with_servers, -> { where('servers_count > 0') }
  scope :accessible_by, ->(user) { user.admin? ? all : none }

  # Class methods
  def self.default
    find_or_create_by!(name: 'Default', slug: 'default') do |group|
      group.description = 'Default group for unassigned servers'
      group.color = '#6B7280' # gray-500
    end
  end

  # Instance methods

  # Get server statistics for this group
  def server_stats
    {
      total: servers.count,
      online: servers.where(status: 'online').count,
      offline: servers.where(status: 'offline').count,
      unreachable: servers.where(status: 'unreachable').count,
      maintenance: servers.where(status: 'maintenance').count
    }
  end

  # Get environment breakdown
  def environment_breakdown
    servers.group(:environment).count
  end

  # Get OS family breakdown
  def os_family_breakdown
    servers.group(:os_family).count
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end

  def update_servers_count
    update_column(:servers_count, servers.count)
  end
end
