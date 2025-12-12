# frozen_string_literal: true

# Service for managing Salt state files on the Salt master
class SaltEditorService
  class DeploymentError < StandardError; end

  class << self
    # Deploy a SaltState to the Salt master
    def deploy_state(salt_state)
      validate_content!(salt_state)
      ensure_directory_exists(salt_state.file_path)
      write_file_to_salt_master(salt_state.file_path, salt_state.content)
      salt_state.mark_deployed!
      { success: true, message: "Deployed to #{salt_state.file_path}" }
    rescue StandardError => e
      Rails.logger.error "SaltEditorService.deploy_state error: #{e.message}"
      { success: false, error: e.message }
    end

    # Remove a SaltState file from the Salt master
    def undeploy_state(salt_state)
      remove_file_from_salt_master(salt_state.file_path)
      salt_state.mark_inactive!
      { success: true, message: "Removed #{salt_state.file_path}" }
    rescue StandardError => e
      Rails.logger.error "SaltEditorService.undeploy_state error: #{e.message}"
      { success: false, error: e.message }
    end

    # Validate YAML content
    # Note: Salt state files use Jinja2 templating, which is not valid YAML
    # We check if content contains Jinja2 syntax and provide appropriate validation
    def validate_yaml(content)
      # Check if content contains Jinja2 templating syntax
      if contains_jinja2?(content)
        return { valid: true, is_jinja2_template: true, message: 'Valid Jinja2 template' }
      end

      # Validate as pure YAML
      YAML.safe_load(content, permitted_classes: [Symbol, Date, Time])
      { valid: true, is_jinja2_template: false }
    rescue Psych::SyntaxError => e
      { valid: false, error: e.message, line: e.line, column: e.column, is_jinja2_template: false }
    end

    # Check if content contains Jinja2 templating syntax
    def contains_jinja2?(content)
      # Common Jinja2 patterns in Salt states:
      # {% ... %} - statements (if, for, set, etc.)
      # {{ ... }} - expressions/variables
      # {# ... #} - comments
      content.match?(/\{%.*?%\}|\{\{.*?\}\}|\{#.*?#\}/m)
    end

    # Apply a state to target minions
    def apply_state(state_name, target, test_mode: false)
      args = [state_name]
      kwargs = test_mode ? { test: true } : {}
      SaltService.run_command(target, 'state.apply', args, kwargs: kwargs)
    end

    # Run an orchestration state
    def run_orchestration(orch_name, pillar_data: {})
      # Orchestration runs on the Salt master using salt-run
      pillar_json = pillar_data.to_json if pillar_data.present?
      cmd = "salt-run state.orchestrate orch.#{orch_name}"
      cmd += " pillar='#{pillar_json}'" if pillar_json.present?
      cmd += " --out=json"

      execute_on_salt_master(cmd)
    end

    # Test a state without applying changes
    def test_state(state_name, target)
      apply_state(state_name, target, test_mode: true)
    end

    # Sync states to Salt master (refresh file_roots cache)
    def sync_states
      execute_on_salt_master('salt-run fileserver.update')
    end

    # Read a file from Salt master (for importing existing states)
    def read_file_from_salt_master(file_path)
      result = SaltService.run_command('salt-master', 'cmd.run', ["cat #{file_path}"])
      if result[:success]
        result[:output]
      else
        nil
      end
    rescue StandardError
      nil
    end

    # List files in a directory on Salt master
    def list_salt_files(directory)
      result = SaltService.run_command('salt-master', 'cmd.run', ["find #{directory} -name '*.sls' -type f"])
      if result[:success]
        result[:output].split("\n").map(&:strip).reject(&:blank?)
      else
        []
      end
    rescue StandardError
      []
    end

    private

    def validate_content!(salt_state)
      return if salt_state.cloud_profile? || salt_state.cloud_provider?

      error = salt_state.yaml_error
      raise DeploymentError, "Invalid YAML at line #{error[:line]}: #{error[:message]}" if error
    end

    def ensure_directory_exists(file_path)
      dir = File.dirname(file_path)
      # Use Salt to create directory on Salt master
      SaltService.run_command('salt-master', 'file.mkdir', [dir])
    end

    def write_file_to_salt_master(file_path, content)
      # Use Salt to write file on Salt master
      # Escape content for safe transmission
      encoded_content = Base64.strict_encode64(content)

      result = SaltService.run_command(
        'salt-master',
        'cmd.run',
        ["echo '#{encoded_content}' | base64 -d > #{file_path}"]
      )

      unless result[:success]
        raise DeploymentError, "Failed to write file: #{result[:error] || result[:output]}"
      end

      # Set proper permissions
      SaltService.run_command('salt-master', 'cmd.run', ["chmod 644 #{file_path}"])
      SaltService.run_command('salt-master', 'cmd.run', ["chown root:root #{file_path}"])
    end

    def remove_file_from_salt_master(file_path)
      result = SaltService.run_command('salt-master', 'cmd.run', ["rm -f #{file_path}"])
      unless result[:success]
        raise DeploymentError, "Failed to remove file: #{result[:error] || result[:output]}"
      end
    end

    def execute_on_salt_master(cmd)
      result = SaltService.run_command('salt-master', 'cmd.run', [cmd])
      if result[:success]
        begin
          JSON.parse(result[:output])
        rescue JSON::ParserError
          result[:output]
        end
      else
        { success: false, error: result[:error] || result[:output] }
      end
    end
  end
end
