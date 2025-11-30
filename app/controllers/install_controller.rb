# frozen_string_literal: true

# Controller for serving Salt minion installation scripts
class InstallController < ApplicationController
  # Skip authentication - this endpoint needs to be public
  skip_before_action :authenticate_user!, only: [:minion]

  # Skip CSRF protection for install scripts (these are GET requests from curl)
  skip_before_action :verify_authenticity_token, only: [:minion]

  def minion
    # Set content type to shell script
    response.headers['Content-Type'] = 'text/plain; charset=utf-8'

    # Log the installation request
    Rails.logger.info "Install script requested from IP: #{request.remote_ip}"

    # Read and process the ERB template
    template_path = Rails.root.join('app', 'views', 'install', 'minion.sh.erb')
    template_content = File.read(template_path)

    # Process ERB
    result = ERB.new(template_content).result(binding)

    # Render the processed script
    render plain: result
  end
end
