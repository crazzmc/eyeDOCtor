#!/usr/bin/env ruby

require 'fileutils'
require 'open-uri'
require 'zip'

TRAVELING_RUBY_VERSION = "20150715-2.2.2"

# Your app's name and version
APP_NAME = "watcher_ai"
VERSION = "1.0.0"

# Create package directories
PACKAGE_DIR = "#{APP_NAME}-#{VERSION}-win32"
FileUtils.rm_rf(PACKAGE_DIR)
FileUtils.mkdir_p("#{PACKAGE_DIR}/lib/app")

# Copy your application files
puts "Copying application files..."
FileUtils.cp(['invoice_processor.rb', 'simple_web.rb', 'Gemfile', 'Gemfile.lock'], "#{PACKAGE_DIR}/lib/app")

# Create the main executable script
puts "Creating main executable..."
exe_contents = <<-EOF
@echo off
SET BUNDLE_GEMFILE=%~dp0lib\\app\\Gemfile
SET PATH=%~dp0lib\\ruby\\bin;%PATH%
"%~dp0lib\\ruby\\bin\\ruby.exe" "%~dp0lib\\app\\simple_web.rb" %*
EOF

File.write("#{PACKAGE_DIR}/#{APP_NAME}.bat", exe_contents)

# Download Traveling Ruby
puts "Downloading Traveling Ruby..."
url = "https://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-#{TRAVELING_RUBY_VERSION}-win32.tar.gz"
`curl -L #{url} -o traveling-ruby.tar.gz`

# Extract Traveling Ruby
puts "Extracting Traveling Ruby..."
FileUtils.mkdir_p("#{PACKAGE_DIR}/lib/ruby")
`tar -xzf traveling-ruby.tar.gz -C #{PACKAGE_DIR}/lib/ruby`
FileUtils.rm("traveling-ruby.tar.gz")

# Create ZIP archive
puts "Creating ZIP archive..."
`zip -r #{PACKAGE_DIR}.zip #{PACKAGE_DIR}`
FileUtils.rm_rf(PACKAGE_DIR)

puts "Packaging complete! The archive is: #{PACKAGE_DIR}.zip" 