class Settings::AppearanceController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @custom_logo = SystemSetting.logo_url
    @company_name = SystemSetting.company_name
    @tagline = SystemSetting.tagline
  end

  def update_logo
    uploaded_file = params[:logo]

    if uploaded_file.blank?
      redirect_to settings_appearance_path, alert: 'Please select a file to upload.'
      return
    end

    # Validate file type
    unless uploaded_file.content_type.in?(['image/png', 'image/jpeg', 'image/jpg', 'image/svg+xml'])
      redirect_to settings_appearance_path, alert: 'Only PNG, JPG, and SVG files are supported.'
      return
    end

    # Validate file size (max 2MB)
    if uploaded_file.size > 2.megabytes
      redirect_to settings_appearance_path, alert: 'Logo file must be less than 2MB.'
      return
    end

    begin
      # Create uploads directory if it doesn't exist
      uploads_dir = Rails.root.join('public', 'uploads')
      FileUtils.mkdir_p(uploads_dir)

      # Generate unique filename
      extension = File.extname(uploaded_file.original_filename)
      filename = "logo-#{Time.current.to_i}#{extension}"
      file_path = uploads_dir.join(filename)

      # Save original file
      File.open(file_path, 'wb') do |file|
        file.write(uploaded_file.read)
      end

      # Auto-resize if needed (only for PNG/JPG, not SVG)
      if uploaded_file.content_type.in?(['image/png', 'image/jpeg', 'image/jpg'])
        resize_logo(file_path)
      end

      # Delete old logo if exists
      old_logo = SystemSetting.get('custom_logo')
      if old_logo.present?
        old_path = Rails.root.join('public', 'uploads', old_logo)
        File.delete(old_path) if File.exist?(old_path)
      end

      # Save new logo filename
      SystemSetting.set('custom_logo', filename, 'file')

      redirect_to settings_appearance_path, notice: 'Logo updated successfully!'
    rescue StandardError => e
      Rails.logger.error "Logo upload failed: #{e.message}"
      redirect_to settings_appearance_path, alert: "Failed to upload logo: #{e.message}"
    end
  end

  def remove_logo
    old_logo = SystemSetting.get('custom_logo')

    if old_logo.present?
      # Delete file
      old_path = Rails.root.join('public', 'uploads', old_logo)
      File.delete(old_path) if File.exist?(old_path)

      # Remove setting
      SystemSetting.find_by(key: 'custom_logo')&.destroy

      redirect_to settings_appearance_path, notice: 'Logo removed. Using default logo.'
    else
      redirect_to settings_appearance_path, alert: 'No custom logo to remove.'
    end
  end

  def update_company_name
    company_name = params[:company_name]

    if company_name.blank?
      redirect_to settings_appearance_path, alert: 'Company name cannot be empty.'
      return
    end

    SystemSetting.set('company_name', company_name)
    redirect_to settings_appearance_path, notice: 'Company name updated successfully!'
  end

  def update_tagline
    tagline = params[:tagline]

    if tagline.blank?
      redirect_to settings_appearance_path, alert: 'Tagline cannot be empty.'
      return
    end

    SystemSetting.set('tagline', tagline)
    redirect_to settings_appearance_path, notice: 'Tagline updated successfully!'
  end

  private

  def resize_logo(file_path)
    require 'mini_magick'

    image = MiniMagick::Image.open(file_path)

    # Target dimensions (navbar height is 64px, logo should be ~32px height)
    max_height = 32
    max_width = 200

    # Only resize if larger than target
    if image.height > max_height || image.width > max_width
      image.resize "#{max_width}x#{max_height}>"
      image.write file_path
    end
  rescue LoadError
    # MiniMagick not available, skip resizing
    Rails.logger.warn "MiniMagick not available, skipping logo resize"
  rescue StandardError => e
    Rails.logger.warn "Logo resize failed: #{e.message}"
  end

  def require_admin!
    redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
  end
end
