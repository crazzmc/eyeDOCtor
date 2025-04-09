#!/usr/bin/env gem exec ruby

require 'bundler/setup'
require 'listen'
require 'fileutils'
require 'logger'
require 'date'
require 'openai'
require 'dotenv'
require 'json'
require 'digest'
require 'base64'
require 'net/http'

# Load environment variables from .env file
Dotenv.load

class InvoiceProcessor
  SUPPORTED_EXTENSIONS = %w[.png .jpg .pdf]
  RATE_LIMIT = 1.0 # Minimum seconds between API calls
  
  # OpenAI API pricing (as of April 2025)
  PRICING = {
    gpt4o_input: 0.01,    # $0.01 per 1K tokens
    gpt4o_output: 0.03,   # $0.03 per 1K tokens
    gpt4o_image: 0.00765  # $0.00765 per image
  }
  
  def initialize(watch_folder: nil, output_folder: nil, blocked_terms: [])
    setup_logger
    @watch_folder = watch_folder
    @output_folder = output_folder
    @blocked_terms = blocked_terms || []
    setup_folders
    setup_openai
    @last_api_call = Time.now.to_f
    @total_cost = 0.0
    @total_queries = 0
    @running = true
    log_info("Invoice Processor initialized")
    log_info("Watching folder: #{@watch_folder}")
    log_info("Output folder: #{@output_folder}")
    log_info("Blocked terms: #{@blocked_terms.join(', ')}") if @blocked_terms && @blocked_terms.any?
  end

  def start
    log_info("Starting to watch #{@watch_folder}")
    
    # Process existing files first
    process_existing_files
    
    # Start a background thread for periodic status updates and manual file checking
    @check_thread = Thread.new do
      loop do
        break unless @running
        log_info("Watcher is active - Last check: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}")
        log_info("Total queries: #{@total_queries}, Total cost: $#{@total_cost.round(4)}")
        
        # Manually check for new files
        current_files = list_current_files
        log_info("Current files in watch folder: #{current_files.join(', ')}")
        
        # Process any new files found
        current_files.each do |file|
          break unless @running
          if SUPPORTED_EXTENSIONS.include?(File.extname(file).downcase)
            log_info("Found new file to process: #{file}")
            # Add a small delay to ensure file is completely written
            sleep(0.5)
            process_file(file)
          end
        end
        
        sleep 5  # Check every 5 seconds
      end
    end
    
    # Set up the file system listener with more verbose logging
    @listener = Listen.to(@watch_folder, 
      ignore: /^\./,  # Ignore hidden files
      wait_for_delay: 0.1,  # Reduced delay for faster response
      force_polling: true,  # Use polling for better reliability
      debug: true,  # Enable debug logging
      latency: 0.1  # Reduce latency for faster response
    ) do |modified, added, removed|
      break unless @running
      log_info("File system event detected!")
      log_info("Modified files: #{modified.join(', ')}") if modified.any?
      log_info("Added files: #{added.join(', ')}") if added.any?
      log_info("Removed files: #{removed.join(', ')}") if removed.any?
      
      # Process both modified and added files
      (modified + added).each do |file|
        break unless @running
        log_info("Processing file from event: #{file}")
        # Add a small delay to ensure file is completely written
        sleep(0.5)
        process_file(file)
      end
    end

    # Start the listener
    log_info("Starting listener...")
    @listener.start
    log_info("Listener started successfully")
  end

  def stop
    @running = false
    @listener.stop if @listener
    @check_thread.join if @check_thread
    log_info("Watcher stopped")
  end

  private

  def list_current_files
    Dir.glob(File.join(@watch_folder, "*")).select { |f| File.file?(f) }
  end

  def setup_openai
    @client = OpenAI::Client.new(
      access_token: ENV['OPENAI_API_KEY'],
      request_timeout: 30,  # 30 second timeout
      uri_base: "https://api.openai.com",  # Explicitly set the API endpoint
    )
  end

  def analyze_with_chatgpt(file_path)
    log_info("Analyzing image with ChatGPT Vision")
    max_retries = 3
    retry_count = 0
    retry_delay = 2  # Initial delay in seconds

    begin
      # Rate limiting
      now = Time.now.to_f
      time_since_last_call = now - @last_api_call
      sleep_time = [0, RATE_LIMIT - time_since_last_call].max
      
      log_info("Rate limiting: sleeping for #{sleep_time} seconds") if sleep_time > 0
      sleep(sleep_time)
      
      @last_api_call = Time.now.to_f
      
      # Read the image file and encode it as base64
      image_data = Base64.strict_encode64(File.read(file_path))
      
      prompt = <<~PROMPT
        Extract from invoice image:
        1. Company Name (vendor at top, exclude Yankee Spirits/Liquor/Liquors)
        2. Invoice Number (from "Invoice #" field)
        3. Invoice Date (from "Invoice Date" field, MM/DD/YYYY)

        Return JSON:
        {
          "company_name": "Example Company Inc",
          "invoice_number": "12345",
          "invoice_date": "04/09/2025"
        }
      PROMPT

      log_info("Sending request to ChatGPT Vision API (attempt #{retry_count + 1}/#{max_retries})...")
      
      # Test the network connection first
      require 'net/http'
      uri = URI('https://api.openai.com')
      Net::HTTP.get_response(uri)

      # Updated API request format based on the documentation
      response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "user",
              content: [
                { 
                  type: "text", 
                  text: prompt 
                },
                {
                  type: "image_url",
                  image_url: {
                    url: "data:image/jpeg;base64,#{image_data}"
                  }
                }
              ]
            }
          ],
          max_tokens: 500
        }
      )

      log_info("Received response from ChatGPT Vision API")
      log_debug("Raw response content: #{response.inspect}")

      # Calculate cost for this query
      calculate_cost(response)
      
      # Extract content from response
      content = response.dig("choices", 0, "message", "content")
      if content.nil?
        log_error("No content in ChatGPT response. Full response: #{response.inspect}")
        raise "No content in ChatGPT response"
      end

      log_debug("Response content: #{content}")
      
      # Try to extract JSON from the response content
      # First try: Look for JSON-like structure
      json_match = content.match(/\{(?:[^{}]|(?:\{[^{}]*\}))*\}/)
      if json_match
        json_str = json_match[0]
        log_debug("Extracted JSON: #{json_str}")
        result = JSON.parse(json_str)
      else
        # Second try: Parse the entire content
        log_debug("No JSON structure found, trying to parse entire content")
        result = JSON.parse(content)
      end

      unless result.is_a?(Hash) && result.key?("company_name") && 
             result.key?("invoice_number") && result.key?("invoice_date")
        raise "Invalid JSON structure in response"
      end

      log_info("ChatGPT Vision analysis successful")
      log_info("Extracted data: company_name=#{result['company_name']}, invoice_number=#{result['invoice_number']}, invoice_date=#{result['invoice_date']}")
      
      result
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Faraday::ConnectionFailed, Net::OpenTimeout => e
      retry_count += 1
      if retry_count < max_retries
        log_warn("Network error: #{e.message}. Retrying in #{retry_delay} seconds... (attempt #{retry_count + 1}/#{max_retries})")
        sleep(retry_delay)
        retry_delay *= 2  # Exponential backoff
        retry
      else
        log_error("Network error after #{max_retries} attempts: #{e.message}")
        {
          "company_name" => "Unknown",
          "invoice_number" => "Unknown",
          "invoice_date" => Date.today.strftime("%m/%d/%Y")
        }
      end
    rescue JSON::ParserError => e
      log_error("Failed to parse JSON from ChatGPT response: #{e.message}")
      log_error("Response content was: #{content}")
      {
        "company_name" => "Unknown",
        "invoice_number" => "Unknown",
        "invoice_date" => Date.today.strftime("%m/%d/%Y")
      }
    rescue => e
      log_error("ChatGPT Vision analysis failed: #{e.message}")
      log_error("Full error: #{e.class}: #{e.message}")
      log_error(e.backtrace.join("\n"))
      {
        "company_name" => "Unknown",
        "invoice_number" => "Unknown",
        "invoice_date" => Date.today.strftime("%m/%d/%Y")
      }
    end
  end
  
  def calculate_cost(response)
    @total_queries += 1
    
    # Get token counts from response
    prompt_tokens = response.dig("usage", "prompt_tokens") || 0
    completion_tokens = response.dig("usage", "completion_tokens") || 0
    
    # Calculate costs
    prompt_cost = (prompt_tokens / 1000.0) * PRICING[:gpt4o_input]
    completion_cost = (completion_tokens / 1000.0) * PRICING[:gpt4o_output]
    image_cost = PRICING[:gpt4o_image]  # One image per request
    
    # Total cost for this query
    query_cost = prompt_cost + completion_cost + image_cost
    @total_cost += query_cost
    
    log_info("API Cost: $#{query_cost.round(4)} (Input: $#{prompt_cost.round(4)}, Output: $#{completion_cost.round(4)}, Image: $#{image_cost.round(4)})")
    log_info("Total API Cost so far: $#{@total_cost.round(4)}")
  end

  def process_existing_files
    log_info("Processing existing files in #{@watch_folder}")
    files = Dir.glob(File.join(@watch_folder, "*")).select { |f| File.file?(f) }
    log_info("Found #{files.size} existing files: #{files.inspect}")
    
    files.each do |file|
      if SUPPORTED_EXTENSIONS.include?(File.extname(file).downcase)
        log_info("Found existing file to process: #{file}")
        process_file(file)
      else
        log_info("Skipping unsupported file: #{file}")
      end
    end
  end

  def setup_logger
    log_dir = File.expand_path('~/Documents/Invoices/logs')
    FileUtils.mkdir_p(log_dir)
    log_file = File.join(log_dir, "invoice_processor_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    
    @logger = Logger.new(log_file)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    
    # Also log to a console logger with a different format to avoid cluttering the terminal
    @console_logger = Logger.new(STDOUT)
    @console_logger.level = Logger::INFO
    @console_logger.formatter = proc do |severity, datetime, progname, msg|
      # Only log important messages to the console
      if severity == Logger::ERROR || msg.include?("Processing file") || msg.include?("API Cost")
        "#{datetime.strftime('%H:%M:%S')} [#{severity}] #{msg}\n"
      else
        nil
      end
    end
    
    @console_logger.info("Invoice Processor initialized")
    @console_logger.info("Log file: #{log_file}")
  end

  def setup_folders
    FileUtils.mkdir_p(@watch_folder)
    FileUtils.mkdir_p(@output_folder)
  end

  def process_file(file_path)
    log_info("Processing file: #{file_path}")
    
    # Skip if file doesn't exist or isn't readable
    unless File.exist?(file_path) && File.readable?(file_path)
      log_error("File does not exist or is not readable: #{file_path}")
      return
    end
    
    # Skip files with FAILED_ prefix
    if File.basename(file_path).start_with?('FAILED_')
      log_info("Skipping previously failed file: #{file_path}")
      return
    end
    
    # Check if file is blocked by terms
    filename = File.basename(file_path).downcase
    if @blocked_terms && @blocked_terms.any? && @blocked_terms.any? { |term| filename.include?(term.downcase) }
      log_info("Skipping blocked file: #{file_path}")
      return
    end
    
    begin
      # Convert PDF to JPG if necessary
      if File.extname(file_path).downcase == '.pdf'
        log_info("Converting PDF to JPG: #{file_path}")
        file_path = convert_pdf_to_jpg(file_path)
      end
      
      # Analyze with ChatGPT Vision
      result = analyze_with_chatgpt(file_path)
      
      # Validate required fields
      unless result["company_name"] && result["invoice_number"] && result["invoice_date"]
        raise "Missing required fields in ChatGPT response"
      end
      
      # Generate new filename
      new_filename = generate_filename(
        result["company_name"],
        result["invoice_number"],
        result["invoice_date"],
        file_path
      )
      
      # Move the file
      move_file(file_path, new_filename)
      log_info("Successfully processed and moved file to: #{new_filename}")
      
    rescue => e
      log_error("Failed to process file #{file_path}: #{e.message}")
      log_error(e.backtrace.join("\n"))
      
      # Move failed file to output folder with FAILED_ prefix
      failed_filename = "FAILED_#{File.basename(file_path)}"
      failed_path = File.join(@output_folder, failed_filename)
      
      begin
        FileUtils.cp(file_path, failed_path)
        log_info("Moved failed file to: #{failed_path}")
      rescue => move_error
        log_error("Failed to move failed file: #{move_error.message}")
      end
    end
  end

  def convert_pdf_to_jpg(pdf_path)
    output_base = File.join(File.dirname(pdf_path), File.basename(pdf_path, '.*'))
    output_path = "#{output_base}-1.jpg"
    
    log_info("Converting PDF to JPG: #{pdf_path}")
    system("pdftoppm -jpeg -r 300 '#{pdf_path}' '#{output_base}'")
    
    output_path
  end

  def generate_filename(company_name, invoice_number, invoice_date, original_path)
    # Convert date string to Date object
    begin
      date = if invoice_date.is_a?(String)
        Date.strptime(invoice_date, "%m/%d/%Y")
      else
        invoice_date
      end
    rescue ArgumentError
      # If the date format is different, try a different format
      begin
        date = Date.parse(invoice_date.to_s)
      rescue ArgumentError
        # If all else fails, use today's date
        date = Date.today
      end
    end

    # Format the filename
    sanitized_company = company_name.gsub(/[^0-9A-Za-z\s]/, '').strip.gsub(/\s+/, '_')
    "#{date.strftime('%Y-%m-%d')}_#{sanitized_company}_#{invoice_number}.pdf"
  end

  def move_file(original_path, new_filename)
    destination = File.join(@output_folder, new_filename)
    log_info("Moving file to: #{destination}")
    FileUtils.mv(original_path, destination)
  end

  def log_info(message)
    @logger.info(message)
    @console_logger.info(message)
  end

  def log_error(message)
    @logger.error(message)
    @console_logger.error(message)
  end

  def log_warn(message)
    @logger.warn(message)
    @console_logger.warn(message)
  end

  def log_debug(message)
    @logger.debug(message)
    @console_logger.debug(message)
  end
end

# Start the processor
processor = InvoiceProcessor.new
processor.start 