class Settings::BackupsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_backup_configuration

  def index
    @backup_config = @backup_configuration

    # Only load histories if we have a persisted configuration
    if @backup_config.persisted?
      @backup_histories = @backup_config.backup_histories.recent.limit(20)
      @last_backup = @backup_histories.first
      @failed_backups_count = @backup_config.backup_histories.failed.where('started_at > ?', 7.days.ago).count
    else
      @backup_histories = []
      @last_backup = nil
      @failed_backups_count = 0
    end
  end

  def update
    # Save the configuration if it's new
    if @backup_configuration.new_record?
      @backup_configuration.assign_attributes(backup_config_params)
      if @backup_configuration.save
        redirect_to settings_backups_path, success: 'Backup configuration saved successfully.'
        return
      end
    else
      if @backup_configuration.update(backup_config_params)
        redirect_to settings_backups_path, success: 'Backup configuration updated successfully.'
        return
      end
    end

    # Re-render form with errors
    @backup_config = @backup_configuration
    if @backup_config.persisted?
      @backup_histories = @backup_config.backup_histories.recent.limit(20)
      @last_backup = @backup_histories.first
      @failed_backups_count = @backup_config.backup_histories.failed.where('started_at > ?', 7.days.ago).count
    else
      @backup_histories = []
      @last_backup = nil
      @failed_backups_count = 0
    end
    render :index, status: :unprocessable_entity
  end

  def test_connection
    # Test Borg repository connection
    result = test_borg_connection

    if result[:success]
      render json: { success: true, message: result[:message] }
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  end

  def run_now
    if @backup_configuration.enabled?
      BorgBackupJob.perform_later
      redirect_to settings_backups_path, success: 'Backup started. Check the history below for progress.'
    else
      redirect_to settings_backups_path, alert: 'Backup is not enabled. Enable it first.'
    end
  end

  def generate_ssh_key
    # Generate ED25519 SSH key pair
    require 'open3'

    temp_key = "/tmp/borg_key_#{Time.current.to_i}"

    begin
      # Generate key pair
      stdout, stderr, status = Open3.capture3("ssh-keygen -t ed25519 -C 'borg-backup@#{ENV['DOMAIN'] || request.host}' -f #{temp_key} -N ''")

      if status.success?
        private_key = File.read(temp_key)
        public_key = File.read("#{temp_key}.pub")

        # Clean up temp files
        File.delete(temp_key) if File.exist?(temp_key)
        File.delete("#{temp_key}.pub") if File.exist?("#{temp_key}.pub")

        render json: {
          success: true,
          private_key: private_key,
          public_key: public_key
        }
      else
        render json: { success: false, message: stderr }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: { success: false, message: e.message }, status: :unprocessable_entity
    end
  end

  def clear_configuration
    # Delete all backup histories
    @backup_configuration.backup_histories.delete_all if @backup_configuration.persisted?

    # Clear all configuration fields
    @backup_configuration.update!(
      repository_url: nil,
      passphrase: nil,
      ssh_key: nil,
      enabled: false,
      last_backup_at: nil
    )

    Rails.logger.info "Backup configuration cleared by user #{current_user.email}"

    redirect_to settings_backups_path, success: 'Backup configuration and history have been completely cleared.'
  rescue StandardError => e
    Rails.logger.error "Failed to clear backup configuration: #{e.message}"
    redirect_to settings_backups_path, alert: "Failed to clear configuration: #{e.message}"
  end

  private

  def set_backup_configuration
    @backup_configuration = BackupConfiguration.current
  end

  def backup_config_params
    params.require(:backup_configuration).permit(
      :repository_url,
      :repository_type,
      :passphrase,
      :ssh_key,
      :backup_schedule,
      :enabled,
      :retention_daily,
      :retention_weekly,
      :retention_monthly
    )
  end

  def test_borg_connection
    return { success: false, message: 'Repository URL not configured' } if @backup_configuration.repository_url.blank?
    return { success: false, message: 'Passphrase not configured' } if @backup_configuration.passphrase.blank?

    require 'open3'

    # Build environment for command
    env = {
      'BORG_REPO' => @backup_configuration.repository_url,
      'BORG_PASSPHRASE' => @backup_configuration.passphrase
    }

    # Add SSH key to environment if configured
    ssh_key_file = nil
    if @backup_configuration.ssh_key.present?
      # Write SSH key to temporary file with proper Unix line endings
      ssh_key_file = Tempfile.new(['borg_key', ''])
      # Convert CRLF to LF (Windows to Unix line endings)
      key_content = @backup_configuration.ssh_key.gsub("\r\n", "\n")
      ssh_key_file.write(key_content)
      ssh_key_file.write("\n") unless key_content.end_with?("\n")
      ssh_key_file.flush
      ssh_key_file.close
      File.chmod(0600, ssh_key_file.path)

      env['BORG_RSH'] = "ssh -i #{ssh_key_file.path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    end

    # Try to list the repository
    stdout, stderr, status = Open3.capture3(env, "borg", "list", "--last", "1")

    # If repository doesn't exist, initialize it
    if !status.success? && (stderr.include?("is not a valid repository") || stderr.include?("does not exist") || stderr.include?("not found"))
      Rails.logger.info "Repository not initialized. Initializing with repokey encryption..."

      init_stdout, init_stderr, init_status = Open3.capture3(env, "borg", "init", "--encryption=repokey")

      if init_status.success?
        return { success: true, message: 'Repository initialized and connection successful! Repository is ready for backups.' }
      else
        return { success: false, message: "Failed to initialize repository: #{init_stderr.present? ? init_stderr : init_stdout}" }
      end
    elsif status.success?
      return { success: true, message: 'Connection successful! Repository is accessible.' }
    else
      return { success: false, message: "Connection failed: #{stderr.present? ? stderr : stdout}" }
    end
  rescue StandardError => e
    Rails.logger.error "Borg test connection error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, message: "Error: #{e.message}" }
  ensure
    # Clean up temporary SSH key file if created
    ssh_key_file&.unlink if ssh_key_file && File.exist?(ssh_key_file.path)
  end

  def require_admin!
    redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
  end
end
