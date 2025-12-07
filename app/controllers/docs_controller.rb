# frozen_string_literal: true

class DocsController < ApplicationController
  before_action :authenticate_user!
  require 'redcarpet'

  # Path to documentation files
  DOCS_PATH = Rails.root.join('docs', 'docs').to_s

  # Main documentation index (Table of Contents)
  def index
    file_path = File.join(DOCS_PATH, 'TABLE_OF_CONTENTS.md')

    if File.exist?(file_path)
      @content = File.read(file_path)
      @title = 'Documentation - Table of Contents'
    else
      @content = generate_index_content
      @title = 'Documentation Index'
    end

    @html_content = render_markdown(@content)
  end

  # Show any documentation page
  def show
    path = params[:path]

    # Security: Prevent directory traversal
    if path.include?('..') || path.start_with?('/')
      return redirect_to docs_path, alert: 'Invalid documentation path.'
    end

    # Sanitize filename (remove directory components)
    filename = File.basename(path, '.md') + '.md'

    # Try to find the file
    file_path = File.join(DOCS_PATH, filename)

    unless File.exist?(file_path)
      return redirect_to docs_path, alert: "Documentation file '#{filename}' not found."
    end

    @content = File.read(file_path)
    @title = extract_title(filename)
    @html_content = render_markdown(@content)

    render :index
  end

  private

  def render_markdown(content)
    # Configure Redcarpet with GitHub-flavored markdown
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: '_blank', rel: 'noopener' },
      with_toc_data: true
    )

    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      highlight: true,
      footnotes: true,
      no_intra_emphasis: true
    )

    # Replace markdown links to other docs with Rails routes
    content = content.gsub(/\[([^\]]+)\]\(([^)]+\.md)\)/) do |match|
      link_text = $1
      file_name = File.basename($2)
      "[#{link_text}](/docs/#{file_name})"
    end

    markdown.render(content)
  end

  def extract_title(filename)
    # Convert filename to title
    # Example: HETZNER_CLOUD_INTEGRATION.md -> Hetzner Cloud Integration
    filename.gsub('.md', '')
            .gsub('_', ' ')
            .split
            .map(&:capitalize)
            .join(' ')
  end

  def generate_index_content
    # Generate a basic index if TABLE_OF_CONTENTS.md doesn't exist
    files = Dir.glob(File.join(DOCS_PATH, '*.md')).sort

    content = "# Server Manager Documentation\n\n"
    content += "Welcome to the Server Manager documentation. Select a document below:\n\n"

    files.each do |file|
      filename = File.basename(file)
      next if filename == 'README.md' # Skip README

      title = extract_title(filename)
      content += "- [#{title}](#{filename})\n"
    end

    content
  end
end
