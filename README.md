# Watcher AI

An intelligent invoice processing system that automatically analyzes and organizes invoice images using OpenAI's GPT-4 Vision API.

## Features

- 🔍 Automatic invoice detection and processing
- 📝 Extracts key information:
  - Company name
  - Invoice number
  - Invoice date
- 🖼️ Supports multiple file formats:
  - JPG/JPEG
  - PNG
  - PDF (automatically converted to JPG)
- 💰 Cost tracking for API usage
- 🔄 Automatic file organization
- ⚡ Real-time file watching
- 🌐 Web-based interface for easy configuration
- 🚫 Blocked terms filtering

## Prerequisites

- Ruby 3.0 or higher
- OpenAI API key
- `pdftoppm` (for PDF processing)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/crazzmc/watcher_ai.git
cd watcher_ai
```

2. Install dependencies:
```bash
bundle install
```

3. Create a `.env` file in the project root:
```
OPENAI_API_KEY=your_api_key_here
```

4. Create required directories:
```bash
mkdir -p ~/Documents/Scans ~/Documents/Invoices
```

## Usage

1. Start the web server:
```bash
./simple_web.rb
```

2. The web interface will automatically open in your default browser
3. Configure your settings:
   - Watch folder (default: `~/Documents/Scans`)
   - Output folder (default: `~/Documents/Invoices`)
   - OpenAI API key
   - Blocked terms (comma-separated)
4. Click "Save Settings" to save your configuration
5. Click "Start Watching" to begin monitoring for new invoices
6. Place invoice images in the watch folder
7. Processed files will be automatically moved to the output folder with standardized naming

## Cost Tracking

The script tracks API usage costs:
- Input tokens: $0.01 per 1K tokens
- Output tokens: $0.03 per 1K tokens
- Image input: $0.00765 per image

Costs are logged for each API call and totaled during runtime.

## Failed Files

If an invoice fails to process, it will be:
1. Copied to the output folder with a "FAILED_" prefix
2. Logged with detailed error information
3. Skipped in future processing attempts

## Packaging for Distribution

### Windows

To create a standalone Windows executable:

```bash
ruby package_windows.rb
```

This will create a `watcher_ai.exe` file that can be distributed to Windows users.

### macOS

To create a standalone macOS application:

```bash
ruby package_macos.rb
```

This will create a `Watcher AI.app` file that can be distributed to macOS users.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

- GitHub: [@crazzmc](https://github.com/crazzmc) 