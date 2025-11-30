class Task < ApplicationRecord
  belongs_to :user
  has_many :task_runs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :command, presence: true
  validates :target_type, presence: true, inclusion: { in: %w[server group all pattern] }
  validate :validate_target

  before_validation :clean_target_values
  before_save :calculate_next_run
  after_save :schedule_job, if: :saved_change_to_enabled?
  after_destroy :remove_scheduled_job

  scope :enabled, -> { where(enabled: true) }
  scope :scheduled, -> { where.not(cron_schedule: [nil, '']) }
  scope :due, -> { enabled.scheduled.where('next_run_at <= ?', Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  def target_name
    case target_type
    when 'server'
      Server.find_by(id: target_id)&.minion_id || 'Unknown Server'
    when 'group'
      Group.find_by(id: target_id)&.name || 'Unknown Group'
    when 'all'
      'All Servers'
    when 'pattern'
      target_pattern || 'Pattern'
    end
  end

  def target_minion_ids
    case target_type
    when 'server'
      server = Server.find_by(id: target_id)
      server&.online? ? [server.minion_id] : []
    when 'group'
      group = Group.find_by(id: target_id)
      group ? group.servers.online.pluck(:minion_id) : []
    when 'all'
      Server.online.pluck(:minion_id)
    when 'pattern'
      Server.online.where('minion_id LIKE ?', target_pattern.gsub('*', '%')).pluck(:minion_id)
    else
      []
    end
  end

  def execute!(triggered_by: nil)
    return if !enabled? && triggered_by.nil?

    task_run = task_runs.create!(
      status: 'pending',
      user: triggered_by
    )

    TaskExecutionJob.perform_later(task_run)
    calculate_next_run && save! if cron_schedule.present?

    task_run
  end

  def last_run
    task_runs.order(created_at: :desc).first
  end

  def running?
    task_runs.where(status: 'running').exists?
  end

  def success_rate
    total = task_runs.where(status: %w[completed failed]).count
    return 0 if total.zero?

    successful = task_runs.where(status: 'completed').count
    (successful.to_f / total * 100).round(1)
  end

  def average_duration
    runs = task_runs.where.not(duration_seconds: nil)
    return 0 if runs.empty?

    runs.average(:duration_seconds).to_i
  end

  private

  def clean_target_values
    # Convert empty strings to nil for target_id and target_pattern
    self.target_id = nil if target_id.blank?
    self.target_pattern = nil if target_pattern.blank?
  end

  def validate_target
    case target_type
    when 'server'
      if target_id.blank?
        errors.add(:target_id, 'must be specified for server target')
      elsif !Server.exists?(target_id)
        errors.add(:target_id, 'server not found')
      end
    when 'group'
      if target_id.blank?
        errors.add(:target_id, 'must be specified for group target')
      elsif !Group.exists?(target_id)
        errors.add(:target_id, 'group not found')
      end
    when 'pattern'
      errors.add(:target_pattern, 'must be specified for pattern target') if target_pattern.blank?
    end
  end

  def calculate_next_run
    return unless cron_schedule.present? && enabled?

    self.next_run_at = CronParser::CronParser.new(cron_schedule).next_time
  rescue => e
    Rails.logger.error "Failed to parse cron schedule: #{e.message}"
    self.next_run_at = nil
  end

  def schedule_job
    # This would integrate with Sidekiq-cron or similar
    # For now, we'll rely on a periodic job that checks for due tasks
  end

  def remove_scheduled_job
    # Remove from scheduler if needed
  end
end

# Module for parsing cron expressions
module CronParser
  extend ActiveSupport::Concern

  class CronValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return if value.blank?

      CronParser.new(value).validate!
    rescue => e
      record.errors.add(attribute, "is not a valid cron expression: #{e.message}")
    end
  end

  class CronParser
    MINUTE = 0..59
    HOUR = 0..23
    DAY = 1..31
    MONTH = 1..12
    WEEKDAY = 0..6

    def initialize(expression)
      @expression = expression
      @parts = expression.split(' ')
    end

    def validate!
      raise ArgumentError, 'Cron expression must have 5 parts' unless @parts.length == 5

      validate_field(@parts[0], MINUTE, 'minute')
      validate_field(@parts[1], HOUR, 'hour')
      validate_field(@parts[2], DAY, 'day of month')
      validate_field(@parts[3], MONTH, 'month')
      validate_field(@parts[4], WEEKDAY, 'day of week')

      true
    end

    def next_time(base_time = Time.current)
      # Simple implementation - would use fugit or similar gem in production
      # For now, return next minute/hour based on simple patterns

      if @expression == '* * * * *' # Every minute
        base_time + 1.minute
      elsif @expression.match?(/^\d+ \* \* \* \*$/) # Every hour at specific minute
        minute = @parts[0].to_i
        next_time = base_time.beginning_of_hour + minute.minutes
        next_time <= base_time ? next_time + 1.hour : next_time
      elsif @expression.match?(/^\d+ \d+ \* \* \*$/) # Daily at specific time
        hour = @parts[1].to_i
        minute = @parts[0].to_i
        next_time = base_time.beginning_of_day + hour.hours + minute.minutes
        next_time <= base_time ? next_time + 1.day : next_time
      else
        # Default to next hour for complex expressions
        base_time + 1.hour
      end
    end

    private

    def validate_field(field, range, name)
      return if field == '*'

      if field.include?('/')
        step = field.split('/')[1]
        raise ArgumentError, "Invalid step value for #{name}" unless step.to_i.positive?
      elsif field.include?(',')
        values = field.split(',')
        values.each do |v|
          validate_single_value(v, range, name)
        end
      elsif field.include?('-')
        start_val, end_val = field.split('-').map(&:to_i)
        raise ArgumentError, "Invalid range for #{name}" unless range.cover?(start_val) && range.cover?(end_val)
      else
        validate_single_value(field, range, name)
      end
    end

    def validate_single_value(value, range, name)
      val = value.to_i
      raise ArgumentError, "Invalid #{name} value: #{value}" unless range.cover?(val)
    end
  end
end