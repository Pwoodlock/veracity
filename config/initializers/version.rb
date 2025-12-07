# frozen_string_literal: true

# Veracity Version Configuration
# This version is displayed in the UI and can be overridden by CI/CD
module Veracity
  # Version number - update this for each release
  VERSION = ENV.fetch("APP_VERSION", "0.0.1").freeze

  # Build/Release ID - set by CI/CD pipeline (e.g., git commit SHA, build number)
  # Example in CI: APP_BUILD_ID=abc123f or APP_BUILD_ID=build-456
  BUILD_ID = ENV["APP_BUILD_ID"]

  # Full version string (includes build ID if available)
  def self.full_version
    if BUILD_ID.present?
      "#{VERSION}+#{BUILD_ID}"
    else
      VERSION
    end
  end

  # Short version for display (truncates long build IDs)
  def self.display_version
    if BUILD_ID.present? && BUILD_ID.length > 8
      "#{VERSION}+#{BUILD_ID[0..7]}"
    else
      full_version
    end
  end
end
