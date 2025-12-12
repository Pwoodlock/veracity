# frozen_string_literal: true

module Admin
  class SaltStatesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_salt_state, only: [:show, :edit, :update, :destroy, :deploy, :undeploy, :clone, :test]

    # GET /admin/salt_states
    def index
      @salt_states = SaltState.ordered

      # Filter by state type
      if params[:type].present?
        @salt_states = @salt_states.where(state_type: params[:type])
      end

      # Filter by category
      if params[:category].present?
        @salt_states = @salt_states.by_category(params[:category])
      end

      # Filter templates vs user-created
      if params[:templates] == 'true'
        @salt_states = @salt_states.templates
      elsif params[:templates] == 'false'
        @salt_states = @salt_states.user_created
      end

      # Filter by active status
      if params[:active] == 'true'
        @salt_states = @salt_states.active
      elsif params[:active] == 'false'
        @salt_states = @salt_states.inactive
      end

      # Search by name
      if params[:search].present?
        @salt_states = @salt_states.where('name ILIKE ?', "%#{params[:search]}%")
      end

      @categories = SaltState::CATEGORIES
      @state_types = SaltState.state_types.keys
    end

    # GET /admin/salt_states/:id
    def show
      @yaml_error = @salt_state.yaml_error
    end

    # GET /admin/salt_states/new
    def new
      @salt_state = SaltState.new(
        state_type: params[:type] || 'state',
        category: params[:category] || 'other',
        content: default_content_for_type(params[:type] || 'state')
      )
      load_api_keys
    end

    # GET /admin/salt_states/:id/edit
    def edit
      @yaml_error = @salt_state.yaml_error
      load_api_keys
    end

    # POST /admin/salt_states
    def create
      @salt_state = SaltState.new(salt_state_params)
      @salt_state.created_by = current_user

      if @salt_state.save
        redirect_to admin_salt_state_path(@salt_state), notice: "Salt state '#{@salt_state.name}' was created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /admin/salt_states/:id
    def update
      if @salt_state.update(salt_state_params)
        redirect_to admin_salt_state_path(@salt_state), notice: "Salt state '#{@salt_state.name}' was updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/salt_states/:id
    def destroy
      name = @salt_state.name
      # Undeploy first if active
      SaltEditorService.undeploy_state(@salt_state) if @salt_state.is_active?
      @salt_state.destroy
      redirect_to admin_salt_states_path, notice: "Salt state '#{name}' was deleted."
    end

    # POST /admin/salt_states/:id/deploy
    def deploy
      result = SaltEditorService.deploy_state(@salt_state)

      if result[:success]
        redirect_to admin_salt_state_path(@salt_state), notice: result[:message]
      else
        redirect_to admin_salt_state_path(@salt_state), alert: "Deployment failed: #{result[:error]}"
      end
    end

    # POST /admin/salt_states/:id/undeploy
    def undeploy
      result = SaltEditorService.undeploy_state(@salt_state)

      if result[:success]
        redirect_to admin_salt_state_path(@salt_state), notice: result[:message]
      else
        redirect_to admin_salt_state_path(@salt_state), alert: "Undeploy failed: #{result[:error]}"
      end
    end

    # POST /admin/salt_states/:id/clone
    def clone
      new_name = "#{@salt_state.name}_copy"
      counter = 1
      while SaltState.exists?(name: new_name, state_type: @salt_state.state_type)
        counter += 1
        new_name = "#{@salt_state.name}_copy#{counter}"
      end

      cloned = @salt_state.clone_as(new_name, current_user)
      cloned.description = "Cloned from #{@salt_state.name}"

      if cloned.save
        redirect_to edit_admin_salt_state_path(cloned), notice: "Cloned as '#{new_name}'. You can now edit it."
      else
        redirect_to admin_salt_state_path(@salt_state), alert: "Failed to clone: #{cloned.errors.full_messages.join(', ')}"
      end
    end

    # POST /admin/salt_states/:id/test
    def test
      target = params[:target] || '*'
      result = SaltEditorService.test_state(@salt_state.name, target)

      if result[:success]
        @test_output = result[:output]
        render :test_result
      else
        redirect_to admin_salt_state_path(@salt_state), alert: "Test failed: #{result[:error]}"
      end
    end

    # POST /admin/salt_states/validate_yaml
    def validate_yaml
      result = SaltEditorService.validate_yaml(params[:content])
      render json: result
    end

    # GET /admin/salt_states/templates
    def templates
      @templates = SaltState.templates.ordered
      @categories = SaltState::CATEGORIES
    end

    private

    def set_salt_state
      @salt_state = SaltState.find(params[:id])
    end

    def salt_state_params
      params.require(:salt_state).permit(:name, :state_type, :content, :description, :category)
    end

    def default_content_for_type(type)
      case type
      when 'state'
        <<~YAML
          # Salt State File
          # See: https://docs.saltproject.io/en/latest/ref/states/all/

          # Example: Install packages
          install_packages:
            pkg.installed:
              - pkgs:
                - vim
                - htop
        YAML
      when 'pillar'
        <<~YAML
          # Salt Pillar Data
          # Sensitive configuration data for minions
          # See: https://docs.saltproject.io/en/latest/topics/pillar/

          # Example pillar data
          app:
            name: myapp
            environment: production
        YAML
      when 'orchestration'
        <<~YAML
          # Salt Orchestration State
          # Multi-step deployment workflow
          # See: https://docs.saltproject.io/en/latest/topics/orchestrate/

          # Step 1: Apply base configuration
          apply_base:
            salt.state:
              - tgt: '*'
              - sls:
                - base

          # Step 2: Apply application state
          apply_app:
            salt.state:
              - tgt: 'role:webserver'
              - tgt_type: grain
              - sls:
                - webserver
              - require:
                - salt: apply_base
        YAML
      when 'cloud_profile'
        <<~YAML
          # Salt Cloud Profile
          # VM provisioning template
          # See: https://docs.saltproject.io/en/latest/topics/cloud/

          my-profile:
            provider: hetzner-cloud
            size: cx21
            image: ubuntu-22.04
            location: fsn1
            ssh_username: root
            minion:
              master: salt.example.com
        YAML
      when 'cloud_provider'
        <<~YAML
          # Salt Cloud Provider
          # API connection configuration
          # See: https://docs.saltproject.io/en/latest/topics/cloud/

          hetzner-cloud:
            driver: hetzner
            api_key: YOUR_API_KEY_HERE
        YAML
      when 'cloud_map'
        <<~YAML
          # Salt Cloud Map
          # Define multiple VMs to provision together
          # See: https://docs.saltproject.io/en/latest/topics/cloud/

          hetzner-cx21:
            - web-01
            - web-02
          hetzner-cx31:
            - db-01
        YAML
      else
        "# Salt configuration file\n"
      end
    end

    def load_api_keys
      # Load available API keys for cloud provider selection
      @hetzner_api_keys = HetznerApiKey.enabled.order(:name)
      @proxmox_api_keys = ProxmoxApiKey.order(:name) rescue []
    end
  end
end
