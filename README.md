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

1. Start the watcher:
```bash
ruby invoice_processor.rb
```

2. Place invoice images in the `~/Documents/Scans` folder
3. Processed files will be automatically moved to `~/Documents/Invoices` with standardized naming

## Cost Tracking

The script tracks API usage costs:
- Input tokens: $0.01 per 1K tokens
- Output tokens: $0.03 per 1K tokens
- Image input: $0.00765 per image

Costs are logged for each API call and totaled during runtime.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

- GitHub: [@crazzmc](https://github.com/crazzmc) 