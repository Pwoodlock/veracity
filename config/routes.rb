Rails.application.routes.draw do
  # Authentication (registrations disabled - users created by admins only)
  devise_for :users, skip: [:registrations], controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks',
    sessions: 'users/sessions'
  }

  # 2FA OTP verification (must be within devise_scope)
  devise_scope :user do
    post 'users/verify_otp', to: 'users/sessions#verify_otp', as: :users_verify_otp
  end

  # Two-Factor Authentication Setup
  resource :two_factor, only: [:show, :new, :create, :destroy], controller: 'two_factor'

  # Documentation (authenticated access)
  get "docs" => "docs#index", as: :docs
  get "docs/*path" => "docs#show"

  # Salt minion installation script (public endpoint)
  get "install-minion.sh" => "install#minion", as: :install_minion

  # Onboarding (minion key management)
  get "onboarding" => "onboarding#index", as: :onboarding
  get "onboarding/install" => "onboarding#install", as: :onboarding_install
  post "onboarding/accept_key" => "onboarding#accept_key", as: :accept_key_onboarding
  post "onboarding/reject_key" => "onboarding#reject_key", as: :reject_key_onboarding
  post "onboarding/refresh" => "onboarding#refresh", as: :refresh_onboarding

  # Users (admin only)
  resources :users do
    member do
      post :toggle_otp
    end
  end

  # Admin namespace for administrative features
  namespace :admin do
    # Salt CLI - Full terminal access for admins
    get 'salt_cli' => 'salt_cli#index', as: :salt_cli
    get 'salt_cli/history' => 'salt_cli#history', as: :salt_cli_history
    post 'salt_cli/execute' => 'salt_cli#execute', as: :salt_cli_execute
    get 'salt_cli/command/:id' => 'salt_cli#show_command', as: :salt_cli_show_command
    delete 'salt_cli/command/:id' => 'salt_cli#destroy_command', as: :salt_cli_command
    delete 'salt_cli/history' => 'salt_cli#clear_history', as: :salt_cli_clear_history

    # Salt Editor - State file management
    resources :salt_states do
      member do
        post :deploy
        post :undeploy
        post :clone
        post :test
      end
      collection do
        post :validate_yaml
        get :templates
      end
    end

    # Gotify Push Notifications Administration
    get 'gotify' => 'gotify#index', as: :gotify
    get 'gotify/applications' => 'gotify#applications', as: :gotify_applications
    post 'gotify/create_application' => 'gotify#create_application', as: :gotify_create_application
    put 'gotify/update_application' => 'gotify#update_application', as: :gotify_update_application
    delete 'gotify/delete_application' => 'gotify#delete_application', as: :gotify_delete_application
    get 'gotify/users' => 'gotify#users', as: :gotify_users
    post 'gotify/create_user' => 'gotify#create_user', as: :gotify_create_user
    put 'gotify/update_user' => 'gotify#update_user', as: :gotify_update_user
    delete 'gotify/delete_user' => 'gotify#delete_user', as: :gotify_delete_user
    get 'gotify/messages' => 'gotify#messages', as: :gotify_messages
    post 'gotify/send_message' => 'gotify#send_message', as: :gotify_send_message
    delete 'gotify/delete_message' => 'gotify#delete_message', as: :gotify_delete_message
    delete 'gotify/delete_app_messages' => 'gotify#delete_app_messages', as: :gotify_delete_app_messages
    get 'gotify/clients' => 'gotify#clients', as: :gotify_clients
    post 'gotify/create_client' => 'gotify#create_client', as: :gotify_create_client
    delete 'gotify/revoke_client' => 'gotify#revoke_client', as: :gotify_revoke_client
    get 'gotify/settings' => 'gotify#settings', as: :gotify_settings
    post 'gotify/update_settings' => 'gotify#update_settings', as: :gotify_update_settings
    post 'gotify/test_connection' => 'gotify#test_connection', as: :gotify_test_connection
  end

  # Settings (Admin only)
  namespace :settings do
    # Appearance Settings
    get 'appearance', to: 'appearance#index', as: :appearance
    post 'appearance/update_logo', to: 'appearance#update_logo', as: :update_logo_appearance
    delete 'appearance/remove_logo', to: 'appearance#remove_logo', as: :remove_logo_appearance
    post 'appearance/update_company_name', to: 'appearance#update_company_name', as: :update_company_name_appearance
    post 'appearance/update_tagline', to: 'appearance#update_tagline', as: :update_tagline_appearance

    resources :backups, only: [:index] do
      collection do
        post :update
        post :test_connection
        post :run_now
        post :generate_ssh_key
        delete :clear_configuration
      end
    end

    resources :hetzner_api_keys do
      member do
        post :test
        post :toggle
      end
    end

    resources :proxmox_api_keys do
      member do
        post :test
        post :toggle
        post :discover_vms
      end
    end

    resources :netbird_setup_keys do
      member do
        post :toggle
        post :deploy
      end
    end

    # Vulnerability Lookup (PyVulnerabilityLookup settings)
    resource :vulnerability_lookup, only: [:update], controller: 'vulnerability_lookup' do
      get :index, on: :collection, action: :index
      post :test_connection, on: :collection
      post :python_info, on: :collection
      post :run_scan, on: :collection
    end

    # Maintenance & Cleanup
    get 'maintenance', to: 'maintenance#index', as: :maintenance
    delete 'maintenance/clear_failed_commands', to: 'maintenance#clear_failed_commands', as: :clear_failed_commands_maintenance
    delete 'maintenance/clear_old_commands', to: 'maintenance#clear_old_commands', as: :clear_old_commands_maintenance
    delete 'maintenance/clear_failed_task_runs', to: 'maintenance#clear_failed_task_runs', as: :clear_failed_task_runs_maintenance
    delete 'maintenance/clear_old_task_runs', to: 'maintenance#clear_old_task_runs', as: :clear_old_task_runs_maintenance
  end

  # Tasks System
  resources :tasks do
    member do
      post :execute
    end
    resources :task_runs, only: [:index, :show] do
      member do
        post :cancel
      end
    end
  end

  resources :task_templates, only: [:index, :show] do
    member do
      get :use
    end
  end

  # CVE Monitoring
  resources :cve_watchlists do
    member do
      post :test   # Test watchlist (run immediate scan)
      get :debug   # Debug API call and response
    end
  end

  resources :vulnerability_alerts do
    collection do
      post :bulk_acknowledge
      post :bulk_resolve
      post :bulk_ignore
    end
    member do
      post :acknowledge
      post :resolve
      post :ignore
    end
  end

  # Groups
  resources :groups do
    member do
      post :manage_servers  # Bulk add/remove servers from group
    end
  end

  # Servers
  resources :servers, only: [:index, :show, :edit, :update, :destroy] do
    collection do
      get :fetch_hetzner_servers  # Fetch servers from Hetzner for dropdown
      get :fetch_proxmox_vms      # Fetch VMs/LXCs from Proxmox for dropdown
    end
    member do
      post :sync
      get :diagnose
      post :manual_refresh_proxmox
      # Hetzner Cloud control actions
      post :start_hetzner
      post :stop_hetzner
      post :reboot_hetzner
      post :refresh_hetzner_status
      get :hetzner_snapshots
      post :create_hetzner_snapshot
      delete :delete_hetzner_snapshot
      # Proxmox VM/LXC control actions
      post :start_proxmox
      post :stop_proxmox
      post :shutdown_proxmox
      post :reboot_proxmox
      post :refresh_proxmox_status
      get :proxmox_snapshots
      post :create_proxmox_snapshot
      post :rollback_proxmox_snapshot
      delete :delete_proxmox_snapshot
    end
  end

  # Commands
  resources :commands, only: [:index, :show]

  # Action Cable for WebSocket connections
  mount ActionCable.server => '/cable'

  # Custom operations dashboard
  get "dashboard" => "dashboard#index", as: :dashboard
  post "dashboard/execute_command" => "dashboard#execute_command", as: :dashboard_execute_command
  post "dashboard/trigger_metrics" => "dashboard#trigger_metrics_collection", as: :dashboard_trigger_metrics
  post "dashboard/trigger_sync" => "dashboard#trigger_sync_minions", as: :dashboard_trigger_sync
  post "dashboard/check_updates" => "dashboard#trigger_check_updates", as: :dashboard_check_updates
  post "dashboard/security_updates" => "dashboard#trigger_security_updates", as: :dashboard_security_updates
  post "dashboard/full_updates" => "dashboard#trigger_full_updates", as: :dashboard_full_updates
  delete "dashboard/clear_failed_commands" => "dashboard#clear_failed_commands", as: :dashboard_clear_failed_commands

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path
  root "dashboard#index"
end
