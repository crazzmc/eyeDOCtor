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
bundle_path = "#{resources_path}/vendor/bundle/ruby/#{RUBY_VERSION}"

# Create app structure
FileUtils.rm_rf(app_path) if File.exist?(app_path)
FileUtils.mkdir_p(macos_path)
FileUtils.mkdir_p(resources_path)
FileUtils.mkdir_p(bundle_path)
FileUtils.mkdir_p(File.join(resources_path, 'public'))

# First install gems in the project directory
puts "Installing gems in project directory..."
system('bundle install')

# Copy icon to public folder
FileUtils.cp('icon.png', File.join(resources_path, 'public', 'icon.png'))

# Create Info.plist
info_plist = <<~XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>watcher_ai</string>
    <key>CFBundleIconFile</key>
    <string>icon.png</string>
    <key>CFBundleIdentifier</key>
    <string>com.eyedocter.app</string>
    <key>CFBundleName</key>
    <string>eyeDOCtor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSEnvironment</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>BUNDLE_PATH</key>
        <string>vendor/bundle</string>
        <key>GEM_HOME</key>
        <string>vendor/bundle</string>
        <key>BUNDLE_GEMFILE</key>
        <string>Gemfile</string>
    </dict>
</dict>
</plist>
XML

File.write("#{contents_path}/Info.plist", info_plist)

# Create launcher script
launcher_script = <<~BASH
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_DIR="$DIR/../Resources"
cd "$RESOURCES_DIR"

# Debug output
echo "Starting launcher script..."
echo "Current directory: $(pwd)"
echo "Ruby version: $(ruby -v)"
echo "Bundler version: $(bundle -v)"

# Set up Ruby environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export BUNDLE_PATH="$RESOURCES_DIR/vendor/bundle"
export GEM_HOME="$RESOURCES_DIR/vendor/bundle"
export BUNDLE_GEMFILE="$RESOURCES_DIR/Gemfile"
export RUBYLIB="$RESOURCES_DIR/vendor/bundle/ruby/#{RUBY_VERSION}/lib:$RUBYLIB"

# Debug environment
echo "Environment variables:"
echo "BUNDLE_PATH=$BUNDLE_PATH"
echo "GEM_HOME=$GEM_HOME"
echo "BUNDLE_GEMFILE=$BUNDLE_GEMFILE"
echo "RUBYLIB=$RUBYLIB"

# Ensure we're using the correct Ruby
if command -v rbenv >/dev/null 2>&1; then
  echo "Using rbenv..."
  eval "$(rbenv init -)"
elif command -v rvm >/dev/null 2>&1; then
  echo "Using rvm..."
  source "$HOME/.rvm/scripts/rvm"
else
  echo "Using system Ruby..."
fi

# Run bundle install if needed
echo "Running bundle install..."
bundle config set --local path 'vendor/bundle'
bundle install --local || bundle install

# Run the application with bundle exec
echo "Starting application..."
exec bundle exec ruby watcher_ai_main.rb 2>&1 | tee -a eyedoctor.log
BASH

File.write("#{macos_path}/watcher_ai", launcher_script)
FileUtils.chmod(0755, "#{macos_path}/watcher_ai")

# Copy application files
FileUtils.cp_r('invoice_processor.rb', resources_path)
FileUtils.cp_r('simple_web.rb', resources_path)
FileUtils.cp_r('Gemfile', resources_path)
FileUtils.cp_r('Gemfile.lock', resources_path)
FileUtils.cp_r('.env', resources_path) if File.exist?('.env')

# Create main script
main_script = <<~RUBY
#!/usr/bin/env ruby

begin
  puts "Initializing application..."
  require 'bundler/setup'
  puts "Bundler setup complete"
  Bundler.setup
  puts "Bundler configuration complete"

  # Start the web server
  puts "Starting #{app_name}..."
  puts "Opening web interface in your browser..."
  
  # Load the web server
  puts "Loading web server..."
  require_relative 'simple_web'
rescue => e
  puts "Error during startup:"
  puts e.message
  puts e.backtrace
  puts "\nPress Enter to exit"
  gets
  exit 1
end
RUBY

File.write("#{resources_path}/watcher_ai_main.rb", main_script)
FileUtils.chmod(0755, "#{resources_path}/watcher_ai_main.rb")

# Install dependencies in the app bundle
puts "Installing dependencies in app bundle..."
Dir.chdir(resources_path) do
  # Set up environment for bundle install
  ENV['BUNDLE_PATH'] = 'vendor/bundle'
  ENV['GEM_HOME'] = 'vendor/bundle'
  ENV['BUNDLE_GEMFILE'] = File.join(Dir.pwd, 'Gemfile')
  
  # Install gems
  system('bundle config set --local path "vendor/bundle"')
  system('bundle install')
end

# Copy the entire vendor/bundle directory from project to app
if File.exist?('vendor/bundle')
  FileUtils.cp_r('vendor/bundle/.', "#{resources_path}/vendor/bundle/")
end

# Set proper permissions
FileUtils.chmod_R(0755, app_path)

puts "Packaging complete! The application is: #{app_path}"
puts "You can distribute this .app file to macOS users." 