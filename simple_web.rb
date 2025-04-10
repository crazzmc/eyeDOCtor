#!/usr/bin/env ruby

require 'sinatra'
require 'dotenv'
require 'json'
require 'redcarpet'
require 'webrick'
require_relative 'invoice_processor'
require 'fileutils'

# Load environment variables
Dotenv.load

# Configure Sinatra logging
set :logging, false
set :server_settings, {
  :Logger => WEBrick::Log::new("/dev/null", 7),
  :AccessLog => []
}

# Global variables
$processor = nil
$watch_thread = nil
$is_running = false
$status = "Ready"
$watch_folder = nil
$output_folder = nil
$api_key = ENV['OPENAI_API_KEY'] || ''
$blocked_terms = ENV['BLOCKED_TERMS'] || ''
$processing_queue = []
$processed_files = []

# Documentation content
DOCUMENTATION = <<~MARKDOWN
# eyeDOCtor - Smart Document Assistant

## What eyeDOCtor Does
This app intelligently examines and organizes your documents by:
- Monitoring your scan folder with AI-powered vision
- Diagnosing and understanding document content
- Prescribing proper names based on content
- Filing them in your organized folder

## Quick Start Guide
1. **Set Up Your Document Folders**
   - Select a folder for incoming documents
   - Choose where you want organized files to go
   - Both folders will be created automatically

2. **Add Your API Key**
   - Enter your OpenAI API key
   - This powers eyeDOCtor's document vision
   - Your key is kept private and secure

3. **Start Document Processing**
   - Click "Start Scanning" to begin
   - Drop any documents into your scan folder
   - eyeDOCtor will automatically examine them

## Supported Documents
- Invoices & Bills
- Medical Records
- Contracts & Agreements
- Letters & Correspondence
- Any document with text

## File Formats
- JPG/JPEG images
- PNG images
- PDF files (automatically converted)

## How Files Are Named
Files are diagnosed and renamed using key information:
- Date (when available)
- Organization or sender name
- Document reference numbers
- Example: "2024-04-15_MedicalCenter_Report123.pdf"

## Troubleshooting
- Check the diagnosis logs in your output folder
- Unprocessed files are marked with "UNDIAGNOSED_" prefix
- Ensure folder permissions are correct
- Verify your API key is valid

## Tips
- Use clear, well-lit scans for best diagnosis
- Allow a few seconds between document scans
- Keep original filenames simple
- Avoid special characters in filenames
MARKDOWN

# Set up Sinatra
configure do
  set :port, 4567
  set :bind, '0.0.0.0'
  set :server, 'webrick'
  set :run, true
end

# Markdown renderer
def markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
    autolink: true,
    tables: true,
    fenced_code_blocks: true
  )
  markdown.render(text)
end

# Function to open the web interface in the default browser
def open_browser
  url = "http://localhost:4567"
  puts "\n" + "="*50
  puts "✨ SERVER IS READY! ✨"
  puts "="*50
  puts "🌎 Opening #{url} in your browser..."
  puts "💡 If the browser doesn't open automatically, please visit the URL manually."
  puts "📋 Press Ctrl+C to stop the server"
  puts "="*50 + "\n"
  
  # Try multiple methods to open the browser
  success = false
  
  # Method 1: Using 'open' command
  if RbConfig::CONFIG['host_os'] =~ /darwin|mac os/
    success = system("open #{url}")
  end
  
  # Method 2: Using 'xdg-open' for Linux
  if !success && (RbConfig::CONFIG['host_os'] =~ /linux|bsd/)
    success = system("xdg-open #{url}")
  end
  
  # Method 3: Using 'start' for Windows
  if !success && (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
    success = system("start #{url}")
  end
  
  # Method 4: Using Python's webbrowser module
  if !success
    begin
      require 'open3'
      Open3.popen3('python3 -c "import webbrowser; webbrowser.open(\'' + url + '\')"')
    rescue
      puts "Please open your browser and navigate to: #{url}"
    end
  end
end

# Start the server and open the browser
Thread.new do
  sleep 2  # Give the server time to start
  open_browser
end

# Handle graceful shutdown
trap('INT') do
  puts "\nShutting down gracefully..."
  if $processor
    $processor.stop
  end
  exit
end

# Load saved settings
def load_settings
  settings_file = File.join(File.dirname(__FILE__), 'settings.json')
  if File.exist?(settings_file)
    settings = JSON.parse(File.read(settings_file))
    $watch_folder = settings['watch_folder']
    $output_folder = settings['output_folder']
    $api_key = settings['api_key']
    $blocked_terms = settings['blocked_terms']
  end
end

# Save settings
def save_settings
  settings = {
    'watch_folder' => $watch_folder,
    'output_folder' => $output_folder,
    'api_key' => $api_key,
    'blocked_terms' => $blocked_terms
  }
  settings_file = File.join(File.dirname(__FILE__), 'settings.json')
  File.write(settings_file, JSON.pretty_generate(settings))
end

# Load settings on startup
load_settings

# Routes
get '/' do
  erb :index
end

# Serve the icon file
get '/icon.png' do
  content_type 'image/png'
  send_file File.join(File.dirname(__FILE__), 'icon.png')
end

post '/start' do
  content_type :json
  
  # Validate inputs
  if $watch_folder.nil? || $watch_folder.empty?
    return { success: false, message: "Please select a scan folder" }.to_json
  end
  
  if $output_folder.nil? || $output_folder.empty?
    return { success: false, message: "Please select an organized folder" }.to_json
  end
  
  unless File.directory?($watch_folder)
    return { success: false, message: "Scan folder does not exist" }.to_json
  end
  
  unless File.directory?($output_folder)
    return { success: false, message: "Organized folder does not exist" }.to_json
  end
  
  if $api_key.empty?
    return { success: false, message: "Please enter your OpenAI API key" }.to_json
  end
  
  # Update environment variable
  ENV['OPENAI_API_KEY'] = $api_key
  ENV['BLOCKED_TERMS'] = $blocked_terms
  
  # Create processor instance
  $processor = InvoiceProcessor.new(
    watch_folder: $watch_folder,
    output_folder: $output_folder,
    blocked_terms: $blocked_terms.split(',').map(&:strip)
  )
  
  # Start processor in a separate thread
  $watch_thread = Thread.new do
    begin
      $processor.start
    rescue => e
      $status = "Error: #{e.message}"
      $is_running = false
    end
  end
  
  $is_running = true
  $status = "Examining documents..."
  
  { success: true, message: "Started examining documents" }.to_json
end

post '/stop' do
  content_type :json
  
  if $is_running
    $processor.stop if $processor
    $watch_thread.join if $watch_thread
    $is_running = false
    $status = "Stopped"
    
    { success: true, message: "Stopped examining documents" }.to_json
  else
    { success: false, message: "Not currently running" }.to_json
  end
end

post '/update_settings' do
  content_type :json
  data = JSON.parse(request.body.read)
  
  $watch_folder = data['watch_folder']
  $output_folder = data['output_folder']
  $api_key = data['api_key']
  $blocked_terms = data['blocked_terms']
  
  # Save settings to file
  save_settings
  
  # Update environment variables
  ENV['OPENAI_API_KEY'] = $api_key
  ENV['BLOCKED_TERMS'] = $blocked_terms
  
  { success: true, message: "Settings saved successfully" }.to_json
end

get '/status' do
  content_type :json
  {
    status: $status,
    watch_folder: $watch_folder,
    output_folder: $output_folder,
    api_key: $api_key,
    blocked_terms: $blocked_terms,
    is_running: $is_running,
    processing_queue: $processing_queue,
    processed_files: $processed_files
  }.to_json
end

get '/select_folder' do
  content_type :json
  
  type = params[:type]
  path = params[:path]
  
  if path.nil? || path.empty?
    return { success: false, message: "No folder path provided" }.to_json
  end
  
  # Expand the tilde to the user's home directory
  expanded_path = path.gsub(/^~/, ENV['HOME'])
  
  # Ensure the path exists and is a directory
  unless File.directory?(expanded_path)
    # Try to create the directory if it doesn't exist
    begin
      FileUtils.mkdir_p(expanded_path)
    rescue => e
      return { success: false, message: "Could not create directory: #{e.message}" }.to_json
    end
  end
  
  # Update the appropriate folder variable
  case type
  when 'watch'
    $watch_folder = expanded_path
  when 'output'
    $output_folder = expanded_path
  else
    return { success: false, message: "Invalid folder type" }.to_json
  end
  
  { success: true, path: expanded_path }.to_json
end

# Views
__END__

@@ layout
<!DOCTYPE html>
<html>
<head>
  <title>Invoice Processor</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.7.2/font/bootstrap-icons.css" rel="stylesheet">
  <style>
    :root {
      --bg-color: #1a1a1a;
      --text-color: #ffffff;
      --card-bg: #2d2d2d;
      --border-color: #404040;
      --input-bg: #333333;
      --input-border: #404040;
      --input-text: #ffffff;
      --btn-primary-bg: #007bff;
      --btn-primary-border: #0056b3;
      --btn-success-bg: #28a745;
      --btn-success-border: #1e7e34;
      --btn-danger-bg: #dc3545;
      --btn-danger-border: #bd2130;
      --btn-outline-bg: transparent;
      --btn-outline-border: #6c757d;
      --btn-outline-text: #6c757d;
      --btn-outline-hover-bg: #6c757d;
      --btn-outline-hover-text: #ffffff;
      --status-running: #28a745;
      --status-stopped: #dc3545;
      --progress-bg: #404040;
      --progress-bar-bg: #007bff;
    }

    [data-theme="light"] {
      --bg-color: #f8f9fa;
      --text-color: #333333;
      --card-bg: #ffffff;
      --border-color: #dee2e6;
      --input-bg: #ffffff;
      --input-border: #ced4da;
      --input-text: #495057;
      --btn-primary-bg: #007bff;
      --btn-primary-border: #0056b3;
      --btn-success-bg: #28a745;
      --btn-success-border: #1e7e34;
      --btn-danger-bg: #dc3545;
      --btn-danger-border: #bd2130;
      --btn-outline-bg: transparent;
      --btn-outline-border: #6c757d;
      --btn-outline-text: #6c757d;
      --btn-outline-hover-bg: #6c757d;
      --btn-outline-hover-text: #ffffff;
      --status-running: #28a745;
      --status-stopped: #dc3545;
      --progress-bg: #e9ecef;
      --progress-bar-bg: #007bff;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.5;
      color: var(--text-color);
      background-color: var(--bg-color);
      padding: 20px;
      transition: background-color 0.3s ease, color 0.3s ease;
      font-size: 0.8rem;
    }

    .container {
      max-width: 800px;
      margin: 0 auto;
    }

    .card {
      background: var(--card-bg);
      border-radius: 12px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.2);
      margin-bottom: 2rem;
      border: 1px solid var(--border-color);
    }

    .card-body {
      padding: 2rem;
    }

    .card-title {
      color: var(--text-color);
      font-weight: 600;
      margin-bottom: 1.25rem;
      font-size: 1rem;
    }

    .form-label {
      font-weight: 500;
      color: var(--text-color);
      margin-bottom: 0.4rem;
      font-size: 0.8rem;
    }

    .form-control {
      background-color: var(--input-bg);
      border-color: var(--input-border);
      color: var(--input-text);
      border-radius: 8px;
      padding: 0.6rem;
      font-size: 0.8rem;
      transition: border-color 0.15s ease-in-out, box-shadow 0.15s ease-in-out;
    }

    .form-control:focus {
      background-color: var(--input-bg);
      border-color: var(--btn-primary-bg);
      color: var(--input-text);
      box-shadow: 0 0 0 0.2rem rgba(0,123,255,0.25);
    }

    .form-control::placeholder {
      color: rgba(255, 255, 255, 0.5);
    }

    [data-theme="light"] .form-control::placeholder {
      color: rgba(0, 0, 0, 0.5);
    }

    .btn {
      padding: 0.6rem 1.25rem;
      font-weight: 500;
      border-radius: 8px;
      transition: all 0.2s ease-in-out;
      font-size: 0.8rem;
    }

    .btn-success {
      background-color: var(--btn-success-bg);
      border-color: var(--btn-success-border);
    }

    .btn-danger {
      background-color: var(--btn-danger-bg);
      border-color: var(--btn-danger-border);
    }

    .btn-primary {
      background-color: var(--btn-primary-bg);
      border-color: var(--btn-primary-border);
    }

    .btn-outline-secondary {
      color: var(--btn-outline-text);
      border-color: var(--btn-outline-border);
      background-color: var(--btn-outline-bg);
    }

    .btn-outline-secondary:hover {
      color: var(--btn-outline-hover-text);
      background-color: var(--btn-outline-hover-bg);
      border-color: var(--btn-outline-border);
    }

    .status-indicator {
      display: inline-block;
      width: 12px;
      height: 12px;
      border-radius: 50%;
      margin-right: 8px;
    }

    .status-running {
      background-color: var(--status-running);
      box-shadow: 0 0 8px var(--status-running);
    }

    .status-stopped {
      background-color: var(--status-stopped);
      box-shadow: 0 0 8px var(--status-stopped);
    }

    .form-text {
      color: var(--text-color);
      opacity: 0.7;
      font-size: 0.75rem;
      margin-top: 0.25rem;
    }

    .text-muted {
      color: var(--text-color) !important;
      opacity: 0.8;
    }

    .folder-input-group {
      display: flex;
      align-items: center;
      gap: 0;
    }

    .folder-input-group .form-control {
      border-top-right-radius: 0;
      border-bottom-right-radius: 0;
    }

    .folder-input-group .btn {
      border-top-left-radius: 0;
      border-bottom-left-radius: 0;
      padding: 0.75rem;
      width: 42px;
    }

    .folder-input-group .btn i {
      font-size: 1.1rem;
    }

    .documentation {
      background: var(--card-bg);
      border-radius: 12px;
      padding: 1.5rem;
      box-shadow: 0 2px 4px rgba(0,0,0,0.2);
      border: 1px solid var(--border-color);
      margin-top: 2rem;
    }

    .documentation h1 {
      color: var(--btn-primary-bg);
      font-size: 1.2rem;
      margin-bottom: 1.25rem;
      font-weight: 600;
    }

    .documentation h2 {
      color: var(--btn-success-bg);
      font-size: 1.1rem;
      margin-top: 1.5rem;
      margin-bottom: 0.75rem;
      font-weight: 600;
    }

    .documentation p {
      margin-bottom: 0.75rem;
      font-size: 0.8rem;
      line-height: 1.5;
    }

    .documentation ul {
      margin-bottom: 0.75rem;
      padding-left: 1.25rem;
    }

    .documentation li {
      margin-bottom: 0.4rem;
      font-size: 0.8rem;
      line-height: 1.5;
    }

    .documentation code {
      background-color: var(--input-bg);
      color: var(--btn-primary-bg);
      padding: 0.2rem 0.4rem;
      border-radius: 4px;
      font-size: 0.75rem;
    }

    .documentation pre {
      background-color: var(--input-bg);
      border: 1px solid var(--border-color);
      padding: 1rem;
      border-radius: 8px;
      overflow-x: auto;
      margin-bottom: 1rem;
    }

    .documentation pre code {
      color: var(--text-color);
      background-color: transparent;
      padding: 0;
    }

    .status-text {
      font-size: 0.8rem;
      font-weight: 500;
    }

    .processing-item {
      font-size: 0.8rem;
    }

    .processing-status {
      font-size: 0.75rem;
    }

    .theme-toggle {
      background: none;
      border: none;
      color: var(--text-color);
      cursor: pointer;
      padding: 0.5rem;
      font-size: 1.5rem;
      transition: color 0.3s ease;
    }

    .theme-toggle:hover {
      color: var(--btn-primary-bg);
    }

    .header-container {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }

    .logo-container {
      display: flex;
      align-items: center;
    }
  </style>
</head>
<body data-theme="dark">
  <div class="container">
    <div class="header-container">
      <div class="logo-container">
        <img src="/icon.png" alt="eyeDOCtor Logo" style="height: 40px; margin-right: 15px;">
        <h3 class="mb-0">eyeDOCtor</h3>
      </div>
      <button class="theme-toggle" onclick="toggleTheme()" title="Toggle dark mode">
        <i class="bi bi-moon-fill"></i>
      </button>
    </div>
    <%= yield %>
  </div>
  
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
  <script>
    // Theme handling
    function setTheme(theme) {
      document.body.setAttribute('data-theme', theme);
      localStorage.setItem('theme', theme);
      updateThemeIcon(theme);
    }

    function toggleTheme() {
      const currentTheme = document.body.getAttribute('data-theme');
      const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
      setTheme(newTheme);
    }

    function updateThemeIcon(theme) {
      const icon = document.querySelector('.theme-toggle i');
      icon.className = theme === 'dark' ? 'bi bi-moon-fill' : 'bi bi-sun-fill';
    }

    // Initialize theme
    const savedTheme = localStorage.getItem('theme') || 'dark';
    setTheme(savedTheme);

    // Update status every 2 seconds
    let isFirstLoad = true;
    
    setInterval(function() {
      fetch('/status')
        .then(response => response.json())
        .then(data => {
          document.getElementById('status-text').textContent = data.status;
          
          // Only update input fields on first load or if they're empty
          if (isFirstLoad) {
            document.getElementById('watch-folder').value = data.watch_folder || '';
            document.getElementById('output-folder').value = data.output_folder || '';
            document.getElementById('api-key').value = data.api_key || '';
            document.getElementById('blocked-terms').value = data.blocked_terms || '';
            isFirstLoad = false;
          } else {
            // Only update empty fields
            if (!document.getElementById('watch-folder').value) {
              document.getElementById('watch-folder').value = data.watch_folder || '';
            }
            if (!document.getElementById('output-folder').value) {
              document.getElementById('output-folder').value = data.output_folder || '';
            }
            if (!document.getElementById('api-key').value) {
              document.getElementById('api-key').value = data.api_key || '';
            }
            if (!document.getElementById('blocked-terms').value) {
              document.getElementById('blocked-terms').value = data.blocked_terms || '';
            }
          }
          
          // Update processing queue
          updateProcessingQueue(data.processing_queue, data.processed_files);
          
          const statusIndicator = document.getElementById('status-indicator');
          if (data.is_running) {
            statusIndicator.className = 'status-indicator status-running';
            document.getElementById('start-btn').disabled = true;
            document.getElementById('stop-btn').disabled = false;
          } else {
            statusIndicator.className = 'status-indicator status-stopped';
            document.getElementById('start-btn').disabled = false;
            document.getElementById('stop-btn').disabled = true;
          }
        });
    }, 2000);
    
    // Update processing queue display
    function updateProcessingQueue(queue, processed) {
      const queueContainer = document.getElementById('processing-files');
      const progressBar = document.getElementById('progress-bar');
      const queueStatus = document.getElementById('queue-status');
      
      // Clear existing items
      queueContainer.innerHTML = '';
      
      // Calculate progress
      const total = queue.length + processed.length;
      const completed = processed.length;
      const progress = total > 0 ? (completed / total) * 100 : 0;
      
      // Update progress bar
      progressBar.style.width = progress + '%';
      progressBar.setAttribute('aria-valuenow', progress);
      
      // Update queue status
      if (total === 0) {
        queueStatus.textContent = 'No files in queue';
      } else {
        queueStatus.textContent = `Processing ${queue.length} of ${total} files`;
      }
      
      // Add processing files
      queue.forEach(file => {
        const item = document.createElement('div');
        item.className = 'processing-item';
        item.innerHTML = `
          <span class="processing-name">${file}</span>
          <span class="processing-status">
            <i class="bi bi-hourglass-split"></i>
          </span>
        `;
        queueContainer.appendChild(item);
      });
      
      // Add processed files
      processed.forEach(file => {
        const item = document.createElement('div');
        item.className = 'processing-item';
        item.innerHTML = `
          <span class="processing-name">${file}</span>
          <span class="processing-status">
            <i class="bi bi-check-circle-fill"></i>
          </span>
        `;
        queueContainer.appendChild(item);
      });
    }
    
    // Toggle API key visibility
    function toggleApiKeyVisibility() {
      const apiKeyInput = document.getElementById('api-key');
      const eyeIcon = document.querySelector('.bi-eye');
      
      if (apiKeyInput.type === 'password') {
        apiKeyInput.type = 'text';
        eyeIcon.classList.remove('bi-eye');
        eyeIcon.classList.add('bi-eye-slash');
      } else {
        apiKeyInput.type = 'password';
        eyeIcon.classList.remove('bi-eye-slash');
        eyeIcon.classList.add('bi-eye');
      }
    }
    
    // Save settings
    function saveSettings() {
      const data = {
        watch_folder: document.getElementById('watch-folder').value,
        output_folder: document.getElementById('output-folder').value,
        api_key: document.getElementById('api-key').value,
        blocked_terms: document.getElementById('blocked-terms').value
      };
      
      fetch('/update_settings', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          alert('Settings saved successfully');
        } else {
          alert(data.message);
        }
      });
    }
    
    // Start watching
    function startWatching() {
      fetch('/start', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
          if (!data.success) {
            alert(data.message);
          }
        });
    }
    
    // Stop watching
    function stopWatching() {
      fetch('/stop', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
          if (!data.success) {
            alert(data.message);
          }
        });
    }
    
    // Select folder
    function selectFolder(type) {
      // Use the native folder picker API if available
      if (window.showDirectoryPicker) {
        window.showDirectoryPicker()
          .then(dirHandle => {
            // Get the directory name
            const dirName = dirHandle.name;
            
            // For security reasons, we need to ask for the full path
            // Use the actual selected folder path
            const defaultPath = `~/Documents/${dirName}`;
            const fullPath = prompt(`Please enter the full path to the "${dirName}" folder:`, defaultPath);
            
            if (fullPath) {
              // Update the input field immediately
              document.getElementById(`${type}-folder`).value = fullPath;
              
              // Send the path to the server
              fetch(`/select_folder?type=${type}&path=${encodeURIComponent(fullPath)}`)
                .then(response => response.json())
                .then(data => {
                  if (!data.success) {
                    alert(data.message);
                  }
                })
                .catch(err => {
                  console.error('Error updating folder:', err);
                  alert('Error updating folder selection');
                });
            }
          })
          .catch(err => {
            console.error('Error selecting folder:', err);
            // Fallback to manual path entry
            const defaultPath = type === 'watch' ? '~/Documents/eyeDOCtor/watch' : '~/Documents/eyeDOCtor/processed';
            const manualPath = prompt(`Please enter the full path to the ${type} folder:`, defaultPath);
            if (manualPath) {
              document.getElementById(`${type}-folder`).value = manualPath;
              fetch(`/select_folder?type=${type}&path=${encodeURIComponent(manualPath)}`)
                .then(response => response.json())
                .then(data => {
                  if (!data.success) {
                    alert(data.message);
                  }
                });
            }
          });
      } else {
        // Fallback for browsers that don't support the Directory Picker API
        const defaultPath = type === 'watch' ? '~/Documents/eyeDOCtor/watch' : '~/Documents/eyeDOCtor/processed';
        const manualPath = prompt(`Please enter the full path to the ${type} folder:`, defaultPath);
        if (manualPath) {
          document.getElementById(`${type}-folder`).value = manualPath;
          fetch(`/select_folder?type=${type}&path=${encodeURIComponent(manualPath)}`)
            .then(response => response.json())
            .then(data => {
              if (!data.success) {
                alert(data.message);
              }
            });
        }
      }
    }
  </script>
</body>
</html>

@@ index
<div class="card mb-4">
  <div class="card-body">
    <h5 class="card-title">Document Processing Queue</h5>
    <div id="queue-panel" class="collapse show">
      <div class="progress mb-3">
        <div id="progress-bar" class="progress-bar" role="progressbar" style="width: 0%"></div>
      </div>
      <div id="queue-status" class="text-muted mb-2">No files in queue</div>
      <div id="processing-files" class="list-group">
        <!-- Processing files will be listed here -->
      </div>
    </div>
  </div>
</div>

<div class="card">
  <div class="card-body">
    <h5 class="card-title">Document Scanner Status</h5>
    <p class="card-text">
      <span id="status-indicator" class="status-indicator status-stopped"></span>
      <span id="status-text text-muted"><%= $status %></span>
    </p>
    
    <div class="mb-3">
      <label for="output-folder" class="form-label">Organized Folder (output):</label>
      <div class="folder-input-group">
        <input type="text" class="form-control" id="output-folder" value="<%= $output_folder %>" readonly placeholder="Choose where to save organized files">
        <button class="btn btn-outline-secondary" onclick="selectFolder('output')" title="Choose folder">
          <i class="bi bi-folder2-open"></i>
        </button>
      </div>
      <div class="form-text">Your organized files will go here</div>
    </div>
    
    <div class="mb-3">
      <label for="watch-folder" class="form-label">Scan Folder (input):</label>
      <div class="folder-input-group">
        <input type="text" class="form-control" id="watch-folder" value="<%= $watch_folder %>" readonly placeholder="Choose where to put your scans">
        <button class="btn btn-outline-secondary" onclick="selectFolder('watch')" title="Choose folder">
          <i class="bi bi-folder2-open"></i>
        </button>
      </div>
      <div class="form-text">Put your scanned documents here</div>
    </div>
    
    <div class="mb-3">
      <label for="api-key" class="form-label">OpenAI API Key:</label>
      <div class="input-group">
        <input type="password" class="form-control" id="api-key" value="<%= $api_key %>" placeholder="Enter your OpenAI API key">
        <button class="btn btn-outline-secondary" type="button" onclick="toggleApiKeyVisibility()">
          <i class="bi bi-eye"></i>
        </button>
      </div>
      <div class="form-text">Required to read and understand your documents</div>
    </div>
    
    <div class="mb-3">
      <label for="blocked-terms" class="form-label">Skip Documents Containing:</label>
      <input type="text" class="form-control" id="blocked-terms" value="<%= $blocked_terms %>" placeholder="e.g. draft, temporary, test">
      <div class="form-text">Words to skip (comma-separated)</div>
    </div>
    
    <div class="d-flex justify-content-between">
      <div>
        <button id="start-btn" class="btn btn-success" onclick="startWatching()">Start Scanning</button>
        <button id="stop-btn" class="btn btn-danger" onclick="stopWatching()" disabled>Stop</button>
      </div>
      <button class="btn btn-primary" onclick="saveSettings()">Save Settings</button>
    </div>
  </div>
</div>

<div class="documentation">
  <%= markdown(DOCUMENTATION) %>
</div>