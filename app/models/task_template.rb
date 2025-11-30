class TaskTemplate < ApplicationRecord
  CATEGORIES = %w[updates maintenance backups monitoring security].freeze

  validates :name, presence: true, length: { maximum: 255 }
  validates :command_template, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category) { where(category: category) }

  def self.categories_with_counts
    active.group(:category).count
  end

  def apply_parameters(params = {})
    command = command_template.dup

    # Merge default parameters with provided ones
    all_params = default_parameters.merge(params.stringify_keys)

    # Replace placeholders in the command
    all_params.each do |key, value|
      command.gsub!("{{#{key}}}", value.to_s)
    end

    command
  end

  def required_parameters
    # Extract parameter names from the template
    command_template.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end

  def missing_parameters(provided_params = {})
    required = required_parameters
    provided = provided_params.stringify_keys.keys
    defaults = default_parameters.keys

    required - provided - defaults
  end

  def create_task(user:, name:, target_type:, target_id: nil, target_pattern: nil, params: {})
    command = apply_parameters(params)

    Task.create!(
      user: user,
      name: name,
      description: description,
      command: command,
      target_type: target_type,
      target_id: target_id,
      target_pattern: target_pattern,
      enabled: true
    )
  end
end