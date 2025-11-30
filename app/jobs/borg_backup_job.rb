class BorgBackupJob < ApplicationJob
  queue_as :default

  def perform
    config = BackupConfiguration.current
    return unless config.enabled?

    # Create backup history record
    history = BackupHistory.create!(
      backup_configuration: config,
      backup_name: "server-manager-#{Time.current.strftime('%Y-%m-%d_%H-%M-%S')}",
      status: 'running',
      started_at: Time.current
    )

    ssh_key_file = nil
    db_backup_dir = nil

    begin
      require 'open3'
      require 'shellwords'
      require 'securerandom'

      # Build environment for Borg commands
      borg_env = {
        'BORG_REPO' => validate_repository_url(config.repository_url),
        'BORG_PASSPHRASE' => config.passphrase
      }

      # Handle SSH key if configured
      if config.ssh_key.present?
        ssh_key_file = create_secure_ssh_key_file(config.ssh_key)

        # Use array-based command construction to prevent injection
        # Build SSH command with properly escaped arguments
        ssh_command_parts = [
          'ssh',
          '-i', ssh_key_file.path,
          '-o', 'StrictHostKeyChecking=no',
          '-o', 'UserKnownHostsFile=/dev/null',
          '-o', 'LogLevel=ERROR'
        ]

        # Join with proper shell escaping
        borg_env['BORG_RSH'] = Shellwords.join(ssh_command_parts)
      end

      # Create temporary directory for database dump with secure random name
      db_backup_dir = create_secure_temp_directory

      # Create PostgreSQL dump using array-based command
      Rails.logger.info "Creating PostgreSQL dump..."
      db_dump_path = File.join(db_backup_dir, 'database.sql.gz')

      # Validate output path
      validate_file_path(db_dump_path)

      # Use array-based command execution to prevent injection
      # Split into two commands: pg_dump | gzip
      pg_dump_command = ['sudo', '-u', 'postgres', 'pg_dump', 'server_manager_production']
      gzip_command = ['gzip']

      # Execute pg_dump
      pg_stdout, pg_stderr, pg_status = Open3.capture3(*pg_dump_command)

      unless pg_status.success?
        raise "Database dump failed: #{pg_stderr}"
      end

      # Compress the output
      File.open(db_dump_path, 'wb') do |file|
        gzip_stdout, gzip_stderr, gzip_status = Open3.capture3(
          *gzip_command,
          stdin_data: pg_stdout,
          binmode: true
        )

        unless gzip_status.success?
          raise "Database compression failed: #{gzip_stderr}"
        end

        file.write(gzip_stdout)
      end

      Rails.logger.info "Database dump created: #{File.size(db_dump_path)} bytes"

      # Prepare paths to backup with validation
      backup_paths = [
        db_backup_dir,
        "/opt/veracity/app/config/master.key",
        "/opt/veracity/app/.env.production",
        "/opt/veracity/app/db/schema.rb"
      ].select { |path| validate_and_check_path(path) }

      # Note: /etc/salt excluded due to permission restrictions on private keys

      # Check if repository exists, initialize if needed
      Rails.logger.info "Checking if Borg repository is initialized..."
      check_command = ["borg", "list", "--last", "1"]
      stdout, stderr, status = Open3.capture3(borg_env, *check_command)

      if !status.success? && (stderr.include?("does not exist") || stderr.include?("Repository") || stderr.include?("not found"))
        Rails.logger.info "Repository not initialized. Initializing with repokey encryption..."
        init_command = ["borg", "init", "--encryption=repokey"]
        stdout, stderr, status = Open3.capture3(borg_env, *init_command)

        if status.success?
          Rails.logger.info "Repository initialized successfully"
        else
          raise "Failed to initialize Borg repository: #{stderr}"
        end
      elsif status.success?
        Rails.logger.info "Repository already initialized"
      else
        Rails.logger.warn "Could not check repository status: #{stderr}"
      end

      # Run Borg backup with validated archive name
      Rails.logger.info "Running Borg backup..."
      archive_name = validate_archive_name(history.backup_name)

      backup_command = [
        "borg", "create",
        "--stats",
        "--compression", "lz4",
        "--exclude-caches",
        "::#{archive_name}",
        *backup_paths
      ]

      stdout, stderr, status = Open3.capture3(borg_env, *backup_command)
      output = stdout + stderr

      unless status.success?
        raise "Borg backup failed with exit code #{status.exitstatus}: #{output}"
      end

      # Parse Borg output for statistics
      parse_borg_output(output, history)

      # Update history
      history.update!(
        status: 'completed',
        completed_at: Time.current,
        duration_seconds: (Time.current - history.started_at).to_i,
        output: output
      )

      # Update last backup time
      config.update!(last_backup_at: Time.current)

      # Send Gotify notification for successful backup
      GotifyNotificationService.notify_backup_status(history)

      # Prune old backups with validated retention parameters
      Rails.logger.info "Pruning old backups..."
      prune_command = [
        "borg", "prune",
        "--keep-daily=#{validate_retention_count(config.retention_daily)}",
        "--keep-weekly=#{validate_retention_count(config.retention_weekly)}",
        "--keep-monthly=#{validate_retention_count(config.retention_monthly)}"
      ]

      stdout, stderr, status = Open3.capture3(borg_env, *prune_command)
      Rails.logger.info "Prune output: #{stdout}#{stderr}"

      Rails.logger.info "Backup completed successfully: #{history.backup_name}"

    rescue StandardError => e
      Rails.logger.error "Borg backup failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      history.update!(
        status: 'failed',
        completed_at: Time.current,
        duration_seconds: (Time.current - history.started_at).to_i,
        error_message: e.message
      )

      # Send Gotify notification for failed backup
      GotifyNotificationService.notify_backup_status(history)

    ensure
      # Cleanup temporary directory - always runs even on error
      cleanup_temp_directory(db_backup_dir)

      # Clean up SSH key file if created
      cleanup_ssh_key_file(ssh_key_file)
    end
  end

  private

  def create_secure_ssh_key_file(ssh_key_content)
    # Create temporary file with secure permissions
    ssh_key_file = Tempfile.new(['borg_backup_key', ''], '/tmp')
    ssh_key_file.close # Close file descriptor before changing permissions

    # Set restrictive permissions before writing content
    File.chmod(0600, ssh_key_file.path)

    # Convert CRLF to LF (Windows to Unix line endings)
    key_content = ssh_key_content.gsub("\r\n", "\n")

    # Validate SSH key format (basic validation)
    unless key_content.match?(/\A-----BEGIN [A-Z0-9 ]+ PRIVATE KEY-----/) ||
           key_content.start_with?('ssh-')
      raise "Invalid SSH key format"
    end

    # Write content to file
    File.open(ssh_key_file.path, 'w', 0600) do |f|
      f.write(key_content)
      f.write("\n") unless key_content.end_with?("\n")
    end

    ssh_key_file
  end

  def create_secure_temp_directory
    # Use SecureRandom to create unpredictable directory name
    secure_suffix = SecureRandom.hex(16)
    db_backup_dir = "/tmp/db-backup-#{secure_suffix}"

    # Validate the path doesn't contain traversal attempts
    validate_file_path(db_backup_dir)

    # Create directory with restrictive permissions
    FileUtils.mkdir_p(db_backup_dir, mode: 0700)

    db_backup_dir
  end

  def validate_repository_url(url)
    # Validate repository URL format
    return url if url.blank?

    # Check for basic URL format (ssh:// or file://)
    unless url.match?(%r{\A(ssh://|file://|/)[a-zA-Z0-9@:./_-]+\z})
      raise "Invalid repository URL format: #{url}"
    end

    url
  end

  def validate_file_path(path)
    # Prevent directory traversal attacks
    if path.include?('..') || path.include?("\0")
      raise "Invalid file path: path traversal detected"
    end

    # Ensure path is absolute
    unless Pathname.new(path).absolute?
      raise "Path must be absolute: #{path}"
    end

    true
  end

  def validate_and_check_path(path)
    validate_file_path(path)
    File.exist?(path)
  end

  def validate_archive_name(name)
    # Ensure archive name contains only safe characters
    # Allow alphanumeric, dash, underscore, and colon
    unless name.match?(/\A[a-zA-Z0-9_:-]+\z/)
      raise "Invalid archive name: #{name}"
    end

    name
  end

  def validate_retention_count(count)
    # Ensure retention count is a valid positive integer
    count_int = count.to_i

    if count_int < 0 || count_int > 1000
      raise "Invalid retention count: #{count}"
    end

    count_int
  end

  def cleanup_temp_directory(db_backup_dir)
    return unless db_backup_dir

    begin
      if File.exist?(db_backup_dir)
        # Validate path before deletion
        validate_file_path(db_backup_dir)

        # Securely remove directory
        FileUtils.rm_rf(db_backup_dir, secure: true)
        Rails.logger.info "Cleaned up temporary directory: #{db_backup_dir}"
      end
    rescue => e
      Rails.logger.error "Failed to cleanup temporary directory #{db_backup_dir}: #{e.message}"
    end
  end

  def cleanup_ssh_key_file(ssh_key_file)
    return unless ssh_key_file

    begin
      # Securely delete the SSH key file
      if ssh_key_file.respond_to?(:path) && File.exist?(ssh_key_file.path)
        # Overwrite file content before deletion for security
        File.open(ssh_key_file.path, 'w') { |f| f.write("\0" * 4096) }
      end

      ssh_key_file.close unless ssh_key_file.closed?
      ssh_key_file.unlink

      Rails.logger.info "Cleaned up SSH key file"
    rescue => e
      Rails.logger.error "Failed to cleanup SSH key file: #{e.message}"
    end
  end

  def parse_borg_output(output, history)
    # Parse Borg statistics from output
    # Example output:
    # Original size: 123456789
    # Compressed size: 98765432
    # Deduplicated size: 45678901
    # Number of files: 42

    if output =~ /Original size:\s+(\d+)/
      history.original_size = $1.to_i
    end

    if output =~ /Compressed size:\s+(\d+)/
      history.compressed_size = $1.to_i
    end

    if output =~ /Deduplicated size:\s+(\d+)/
      history.deduplicated_size = $1.to_i
    end

    if output =~ /Number of files:\s+(\d+)/
      history.files_count = $1.to_i
    end

    history.save
  end
end
