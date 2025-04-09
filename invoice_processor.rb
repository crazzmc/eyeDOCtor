#!/usr/bin/env ruby

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
  WATCH_FOLDER = File.expand_path('~/Documents/Scans')
  OUTPUT_FOLDER = File.expand_path('~/Documents/Invoices')
  SUPPORTED_EXTENSIONS = %w[.png .jpg .pdf]
  RATE_LIMIT = 1.0 # Minimum seconds between API calls
  
  # OpenAI API pricing (as of April 2025)
  PRICING = {
    gpt4o_input: 0.01,    # $0.01 per 1K tokens
    gpt4o_output: 0.03,   # $0.03 per 1K tokens
    gpt4o_image: 0.00765  # $0.00765 per image
  }
  
  def initialize
    setup_logger
    setup_folders
    setup_openai
    @last_api_call = Time.now.to_f
    @total_cost = 0.0
    @total_queries = 0
    @logger.info("Invoice Processor initialized")
    @logger.info("Watching folder: #{WATCH_FOLDER}")
    @logger.info("Output folder: #{OUTPUT_FOLDER}")
  end

  def start
    @logger.info("Starting to watch #{WATCH_FOLDER}")
    
    # Process existing files first
    process_existing_files
    
    # Start a background thread for periodic status updates and manual file checking
    Thread.new do
      loop do
        @logger.info("Watcher is active - Last check: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}")
        @logger.info("Total queries: #{@total_queries}, Total cost: $#{@total_cost.round(4)}")
        
        # Manually check for new files
        current_files = list_current_files
        @logger.info("Current files in watch folder: #{current_files.join(', ')}")
        
        # Process any new files found
        current_files.each do |file|
          if SUPPORTED_EXTENSIONS.include?(File.extname(file).downcase)
            @logger.info("Found new file to process: #{file}")
            # Add a small delay to ensure file is completely written
            sleep(0.5)
            process_file(file)
          end
        end
        
        sleep 5  # Check every 5 seconds
      end
    end
    
    # Set up the file system listener with more verbose logging
    listener = Listen.to(WATCH_FOLDER, 
      ignore: /^\./,  # Ignore hidden files
      wait_for_delay: 0.1,  # Reduced delay for faster response
      force_polling: true,  # Use polling for better reliability
      debug: true,  # Enable debug logging
      latency: 0.1  # Reduce latency for faster response
    ) do |modified, added, removed|
      @logger.info("File system event detected!")
      @logger.info("Modified files: #{modified.join(', ')}") if modified.any?
      @logger.info("Added files: #{added.join(', ')}") if added.any?
      @logger.info("Removed files: #{removed.join(', ')}") if removed.any?
      
      # Process both modified and added files
      (modified + added).each do |file|
        @logger.info("Processing file from event: #{file}")
        # Add a small delay to ensure file is completely written
        sleep(0.5)
        process_file(file)
      end
    end

    # Start the listener
    @logger.info("Starting listener...")
    listener.start
    @logger.info("Listener started successfully")
    
    # Keep the main thread alive
    begin
      loop do
        sleep 1
      end
    rescue Interrupt
      @logger.info("Shutting down gracefully...")
      @logger.info("Final stats: #{@total_queries} queries, Total cost: $#{@total_cost.round(4)}")
      listener.stop
    end
  end

  private

  def list_current_files
    Dir.glob(File.join(WATCH_FOLDER, "*")).select { |f| File.file?(f) }
  end

  def setup_openai
    @client = OpenAI::Client.new(
      access_token: ENV['OPENAI_API_KEY'],
      request_timeout: 30,  # 30 second timeout
      uri_base: "https://api.openai.com",  # Explicitly set the API endpoint
    )
  end

  def analyze_with_chatgpt(file_path)
    @logger.info("Analyzing image with ChatGPT Vision")
    max_retries = 3
    retry_count = 0
    retry_delay = 2  # Initial delay in seconds

    begin
      # Rate limiting
      now = Time.now.to_f
      time_since_last_call = now - @last_api_call
      sleep_time = [0, RATE_LIMIT - time_since_last_call].max
      
      @logger.info("Rate limiting: sleeping for #{sleep_time} seconds") if sleep_time > 0
      sleep(sleep_time)
      
      @last_api_call = Time.now.to_f
      
      # Read the image file and encode it as base64
      image_data = Base64.strict_encode64(File.read(file_path))
      
      prompt = <<~PROMPT
        Analyze this invoice image and extract the following three fields in strict JSON format:
        
        1. **Company Name** (Sender):
          - This is the name of the company that **sent** or **issued** the invoice (the vendor/supplier).
          - DO NOT return any of the following names: "Yankee Spirits LLC", "Yankee Liquor", or "Yankee Liquors". These are the billing **recipient**.
          - Look for the company name prominently displayed at the very top of the document, often in large or bold letters.
          - Often this name appears above or near the vendor's address, phone number, or logo.
          - Include the full legal name, such as "Martignetti Companies" or "Connecticut Distributors Inc".
          - Company names may include suffixes like "Inc", "LLC", "Corp", "Co.", "Ltd", etc. Include them if shown.

        2. **Invoice Number**:
          - Look for fields labeled "Invoice #", "Invoice Number", or similar.
          - Include the full number or alphanumeric code shown.

        3. **Invoice Date**:
          - Look for the label "Invoice Date" followed by a date in MM/DD/YYYY format.
          - Return the date exactly as shown.

        Return ONLY a valid JSON object with these three fields, like this:
        {
          "company_name": "Example Company Inc",
          "invoice_number": "12345",
          "invoice_date": "04/09/2025"
        }
      PROMPT

      @logger.info("Sending request to ChatGPT Vision API (attempt #{retry_count + 1}/#{max_retries})...")
      
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
          max_tokens: 1000
        }
      )

      @logger.info("Received response from ChatGPT Vision API")
      @logger.debug("Raw response content: #{response.inspect}")

      # Calculate cost for this query
      calculate_cost(response)
      
      # Extract content from response
      content = response.dig("choices", 0, "message", "content")
      if content.nil?
        @logger.error("No content in ChatGPT response. Full response: #{response.inspect}")
        raise "No content in ChatGPT response"
      end

      @logger.debug("Response content: #{content}")
      
      # Try to extract JSON from the response content
      # First try: Look for JSON-like structure
      json_match = content.match(/\{(?:[^{}]|(?:\{[^{}]*\}))*\}/)
      if json_match
        json_str = json_match[0]
        @logger.debug("Extracted JSON: #{json_str}")
        result = JSON.parse(json_str)
      else
        # Second try: Parse the entire content
        @logger.debug("No JSON structure found, trying to parse entire content")
        result = JSON.parse(content)
      end

      unless result.is_a?(Hash) && result.key?("company_name") && 
             result.key?("invoice_number") && result.key?("invoice_date")
        raise "Invalid JSON structure in response"
      end

      @logger.info("ChatGPT Vision analysis successful")
      @logger.info("Extracted data: company_name=#{result['company_name']}, invoice_number=#{result['invoice_number']}, invoice_date=#{result['invoice_date']}")
      
      result
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Faraday::ConnectionFailed, Net::OpenTimeout => e
      retry_count += 1
      if retry_count < max_retries
        @logger.warn("Network error: #{e.message}. Retrying in #{retry_delay} seconds... (attempt #{retry_count + 1}/#{max_retries})")
        sleep(retry_delay)
        retry_delay *= 2  # Exponential backoff
        retry
      else
        @logger.error("Network error after #{max_retries} attempts: #{e.message}")
        {
          "company_name" => "Unknown",
          "invoice_number" => "Unknown",
          "invoice_date" => Date.today.strftime("%m/%d/%Y")
        }
      end
    rescue JSON::ParserError => e
      @logger.error("Failed to parse JSON from ChatGPT response: #{e.message}")
      @logger.error("Response content was: #{content}")
      {
        "company_name" => "Unknown",
        "invoice_number" => "Unknown",
        "invoice_date" => Date.today.strftime("%m/%d/%Y")
      }
    rescue => e
      @logger.error("ChatGPT Vision analysis failed: #{e.message}")
      @logger.error("Full error: #{e.class}: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
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
    
    @logger.info("API Cost: $#{query_cost.round(4)} (Input: $#{prompt_cost.round(4)}, Output: $#{completion_cost.round(4)}, Image: $#{image_cost.round(4)})")
    @logger.info("Total API Cost so far: $#{@total_cost.round(4)}")
  end

  def process_existing_files
    @logger.info("Processing existing files in #{WATCH_FOLDER}")
    files = Dir.glob(File.join(WATCH_FOLDER, "*")).select { |f| File.file?(f) }
    @logger.info("Found #{files.size} existing files: #{files.inspect}")
    
    files.each do |file|
      if SUPPORTED_EXTENSIONS.include?(File.extname(file).downcase)
        @logger.info("Found existing file to process: #{file}")
        process_file(file)
      else
        @logger.info("Skipping unsupported file: #{file}")
      end
    end
  end

  def setup_logger
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
  end

  def setup_folders
    FileUtils.mkdir_p(WATCH_FOLDER)
    FileUtils.mkdir_p(OUTPUT_FOLDER)
  end

  def process_file(file_path)
    @logger.info("Processing file: #{file_path}")
    
    begin
      # Check if file exists and is readable
      unless File.exist?(file_path)
        @logger.error("File does not exist: #{file_path}")
        return
      end
      
      unless File.readable?(file_path)
        @logger.error("File is not readable: #{file_path}")
        return
      end
      
      # Convert PDF to JPG if necessary
      image_path = if File.extname(file_path).downcase == '.pdf'
        convert_pdf_to_jpg(file_path)
      else
        file_path
      end

      # Analyze with ChatGPT Vision
      result = analyze_with_chatgpt(image_path)
      
      # Validate the result
      if result["invoice_date"].nil? || result["invoice_date"].empty?
        @logger.error("No invoice date found in the analysis result")
        result["invoice_date"] = Date.today.strftime("%m/%d/%Y")
      end
      
      if result["company_name"].nil? || result["company_name"].empty?
        @logger.error("No company name found in the analysis result")
        result["company_name"] = "Unknown_Company"
      end
      
      if result["invoice_number"].nil? || result["invoice_number"].empty?
        @logger.error("No invoice number found in the analysis result")
        result["invoice_number"] = "Unknown"
      end
      
      # Parse the date with error handling
      begin
        invoice_date = Date.strptime(result["invoice_date"], "%m/%d/%Y")
      rescue ArgumentError => e
        @logger.error("Error parsing date '#{result["invoice_date"]}': #{e.message}")
        invoice_date = Date.today
      end
      
      # Generate new filename
      new_filename = generate_filename(
        result["company_name"],
        result["invoice_number"],
        invoice_date,
        file_path
      )
      
      # Move file to output folder
      move_file(file_path, new_filename)
      
      # Clean up temporary JPG if it was created from PDF
      FileUtils.rm(image_path) if image_path != file_path
    rescue => e
      @logger.error("Error processing file #{file_path}: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
    end
  end

  def convert_pdf_to_jpg(pdf_path)
    output_base = File.join(File.dirname(pdf_path), File.basename(pdf_path, '.*'))
    output_path = "#{output_base}-1.jpg"
    
    @logger.info("Converting PDF to JPG: #{pdf_path}")
    system("pdftoppm -jpeg -r 300 '#{pdf_path}' '#{output_base}'")
    
    output_path
  end

  def generate_filename(company_name, invoice_number, date, original_path)
    extension = File.extname(original_path)
    sanitized_company = company_name.gsub(/[^a-zA-Z0-9]/, '_')
    "#{sanitized_company}_#{invoice_number}_#{date.strftime('%Y-%m-%d')}#{extension}"
  end

  def move_file(original_path, new_filename)
    destination = File.join(OUTPUT_FOLDER, new_filename)
    @logger.info("Moving file to: #{destination}")
    FileUtils.mv(original_path, destination)
  end
end

# Start the processor
processor = InvoiceProcessor.new
processor.start 