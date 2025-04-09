#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'erb'

# Ensure we're in the project root
Dir.chdir(File.dirname(__FILE__))

# Configuration
ruby_version = RUBY_VERSION
app_name = "eyeDOCtor"
app_path = "#{app_name}.app"
contents_path = "#{app_path}/Contents"
macos_path = "#{contents_path}/MacOS"
resources_path = "#{contents_path}/Resources"

# Create directories
FileUtils.mkdir_p(macos_path)
FileUtils.mkdir_p(resources_path)

# Create Info.plist
info_plist = <<~XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>watcher_ai</string>
  <key>CFBundleIdentifier</key>
  <string>com.watcher.ai</string>
  <key>CFBundleName</key>
  <string>#{app_name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
XML

File.write("#{contents_path}/Info.plist", info_plist)

# Create launcher script
launcher_script = <<~BASH
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR/../Resources"
./watcher_ai
BASH

File.write("#{macos_path}/watcher_ai", launcher_script)
FileUtils.chmod(0755, "#{macos_path}/watcher_ai")

# Create a temporary main script that will be packaged
main_script = <<~RUBY
#!/usr/bin/env ruby

require 'bundler/setup'
require_relative 'invoice_processor'
require_relative 'simple_web'

# Start the web server
puts "Starting #{app_name}..."
puts "Opening web interface in your browser..."

# The web server will automatically open the browser
require 'simple_web'
RUBY

File.write("#{resources_path}/watcher_ai_main.rb", main_script)

# Copy necessary files to Resources
FileUtils.cp('invoice_processor.rb', resources_path)
FileUtils.cp('simple_web.rb', resources_path)
FileUtils.cp('Gemfile', resources_path) if File.exist?('Gemfile')
FileUtils.cp('Gemfile.lock', resources_path) if File.exist?('Gemfile.lock')

# Create a wrapper script that installs dependencies and runs the app
wrapper_script = <<~BASH
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Install dependencies if needed
if [ ! -d "vendor" ]; then
  echo "Installing dependencies..."
  bundle install --path vendor
fi

# Run the application
ruby watcher_ai_main.rb
BASH

File.write("#{resources_path}/watcher_ai", wrapper_script)
FileUtils.chmod(0755, "#{resources_path}/watcher_ai")

puts "Packaging complete! The application is: #{app_path}"
puts "You can distribute this .app file to macOS users." 