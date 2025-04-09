#!/usr/bin/env ruby

require 'sinatra'
require 'dotenv'
require 'json'
require 'redcarpet'
require_relative 'invoice_processor'

# Load environment variables
Dotenv.load

# Global variables
$processor = nil
$watch_thread = nil
$is_running = false
$status = "Ready"
$watch_folder = nil
$output_folder = nil
$api_key = ENV['OPENAI_API_KEY'] || ''
$blocked_terms = ENV['BLOCKED_TERMS'] || ''

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
set :port, 4567
set :bind, '0.0.0.0'
set :server, 'webrick'

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
  
  case RbConfig::CONFIG['host_os']
  when /mswin|mingw|cygwin/
    system("start #{url}")
  when /darwin|mac os/
    system("open #{url}")
  when /linux|bsd/
    system("xdg-open #{url}")
  else
    puts "Please open your browser and navigate to: #{url}"
  end
end

# Start the server and open the browser
Thread.new do
  sleep 3  # Give the server a moment to start
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

# Routes
get '/' do
  erb :index
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
  
  $watch_folder = data['watch_folder'] if data['watch_folder']
  $output_folder = data['output_folder'] if data['output_folder']
  $api_key = data['api_key'] if data['api_key']
  $blocked_terms = data['blocked_terms'] if data['blocked_terms']
  
  { success: true, message: "Settings updated" }.to_json
end

get '/status' do
  content_type :json
  
  {
    is_running: $is_running,
    status: $status,
    watch_folder: $watch_folder,
    output_folder: $output_folder,
    api_key: $api_key.empty? ? '' : '********',
    blocked_terms: $blocked_terms
  }.to_json
end

get '/select_folder' do
  content_type :json
  folder_type = params['type']
  folder_path = params['path']
  
  if folder_type == 'watch' && File.directory?(folder_path)
    $watch_folder = folder_path
  elsif folder_type == 'output' && File.directory?(folder_path)
    $output_folder = folder_path
  end
  
  { success: true, path: folder_type == 'watch' ? $watch_folder : $output_folder }.to_json
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
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      background-color: #f8f9fa;
      padding: 20px;
    }

    .container {
      max-width: 800px;
      margin: 0 auto;
    }

    .card {
      background: white;
      border-radius: 12px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      margin-bottom: 2rem;
    }

    .card-body {
      padding: 2rem;
    }

    .card-title {
      color: #2c3e50;
      font-weight: 600;
      margin-bottom: 1.5rem;
    }

    .form-label {
      font-weight: 500;
      color: #495057;
      margin-bottom: 0.5rem;
    }

    .form-control {
      border-radius: 8px;
      border: 1px solid #ced4da;
      padding: 0.75rem;
      transition: border-color 0.15s ease-in-out, box-shadow 0.15s ease-in-out;
    }

    .form-control:focus {
      border-color: #80bdff;
      box-shadow: 0 0 0 0.2rem rgba(0,123,255,0.25);
    }

    .folder-input-group {
      display: flex;
      gap: 10px;
    }

    .folder-input-group .form-control {
      flex: 1;
    }

    .btn {
      padding: 0.75rem 1.5rem;
      font-weight: 500;
      border-radius: 8px;
      transition: all 0.2s ease-in-out;
    }

    .btn-success {
      background-color: #28a745;
      border-color: #28a745;
    }

    .btn-success:hover {
      background-color: #218838;
      border-color: #1e7e34;
    }

    .btn-danger {
      background-color: #dc3545;
      border-color: #dc3545;
    }

    .btn-danger:hover {
      background-color: #c82333;
      border-color: #bd2130;
    }

    .btn-primary {
      background-color: #007bff;
      border-color: #007bff;
    }

    .btn-primary:hover {
      background-color: #0069d9;
      border-color: #0062cc;
    }

    .btn-outline-secondary {
      color: #6c757d;
      border-color: #6c757d;
    }

    .btn-outline-secondary:hover {
      color: #fff;
      background-color: #6c757d;
      border-color: #6c757d;
    }

    .status-indicator {
      display: inline-block;
      width: 12px;
      height: 12px;
      border-radius: 50%;
      margin-right: 8px;
    }

    .status-stopped {
      background-color: #dc3545;
    }

    .status-running {
      background-color: #28a745;
    }

    .form-text {
      color: #6c757d;
      font-size: 0.875rem;
      margin-top: 0.25rem;
    }

    .documentation {
      background: white;
      border-radius: 12px;
      padding: 2rem;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }

    .documentation h1 {
      color: #2c3e50;
      font-size: 1.75rem;
      margin-bottom: 1.5rem;
    }

    .documentation h2 {
      color: #34495e;
      font-size: 1.5rem;
      margin-top: 2rem;
      margin-bottom: 1rem;
    }

    .documentation p {
      margin-bottom: 1rem;
    }

    .documentation ul {
      margin-bottom: 1rem;
      padding-left: 1.5rem;
    }

    .documentation li {
      margin-bottom: 0.5rem;
    }

    .documentation code {
      background-color: #f8f9fa;
      padding: 0.2rem 0.4rem;
      border-radius: 4px;
      font-size: 0.875rem;
    }

    .documentation pre {
      background-color: #f8f9fa;
      padding: 1rem;
      border-radius: 8px;
      overflow-x: auto;
      margin-bottom: 1rem;
    }

    .documentation pre code {
      background-color: transparent;
      padding: 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1 class="mb-4">Invoice Processor</h1>
    <%= yield %>
  </div>
  
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
  <script>
    // Update status every 2 seconds
    setInterval(function() {
      fetch('/status')
        .then(response => response.json())
        .then(data => {
          document.getElementById('status-text').textContent = data.status;
          document.getElementById('watch-folder').value = data.watch_folder;
          document.getElementById('output-folder').value = data.output_folder;
          document.getElementById('api-key').value = data.api_key;
          document.getElementById('blocked-terms').value = data.blocked_terms;
          
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

    // Select folder
    function selectFolder(type) {
      const input = document.createElement('input');
      input.type = 'file';
      input.webkitdirectory = true;
      input.directory = true;
      
      input.onchange = function(e) {
        const path = e.target.files[0].path.split('/').slice(0, -1).join('/');
        fetch(`/select_folder?type=${type}&path=${encodeURIComponent(path)}`)
          .then(response => response.json())
          .then(data => {
            if (data.success) {
              document.getElementById(`${type}-folder`).value = data.path;
            }
          });
      };
      
      input.click();
    }
  </script>
</body>
</html>

@@ index
<div class="card">
  <div class="card-body">
    <h5 class="card-title">Document Scanner Status</h5>
    <p class="card-text">
      <span id="status-indicator" class="status-indicator status-stopped"></span>
      <span id="status-text"><%= $status %></span>
    </p>
    
    <div class="mb-3">
      <label for="watch-folder" class="form-label">Scan Folder:</label>
      <div class="folder-input-group">
        <input type="text" class="form-control" id="watch-folder" value="<%= $watch_folder %>" readonly placeholder="Choose where to put your scans">
        <button class="btn btn-outline-secondary" onclick="selectFolder('watch')">Choose Folder</button>
      </div>
      <div class="form-text">Put your scanned documents here</div>
    </div>
    
    <div class="mb-3">
      <label for="output-folder" class="form-label">Organized Folder:</label>
      <div class="folder-input-group">
        <input type="text" class="form-control" id="output-folder" value="<%= $output_folder %>" readonly placeholder="Choose where to save organized files">
        <button class="btn btn-outline-secondary" onclick="selectFolder('output')">Choose Folder</button>
      </div>
      <div class="form-text">Your organized files will go here</div>
    </div>
    
    <div class="mb-3">
      <label for="api-key" class="form-label">OpenAI API Key:</label>
      <input type="password" class="form-control" id="api-key" value="<%= $api_key %>" placeholder="Enter your OpenAI API key">
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