# eyeDOCtor

Your intelligent document assistant that examines, diagnoses, and organizes your documents with AI-powered vision.

## Features

- 👁️ AI-powered document vision and analysis
- 🏥 Smart document diagnosis and classification
- 📝 Intelligent file naming based on content
- 📁 Automated document organization
- 🔒 Secure and private processing
- 🌐 User-friendly web interface

## Installation

### Prerequisites

- Ruby 2.7 or higher
- Bundler gem
- OpenAI API key

### Quick Start

1. Clone the repository:
```bash
git clone https://github.com/crazzmc/eyedoctor.git
cd eyedoctor
```

2. Install dependencies:
```bash
bundle install
```

3. Start the application:
```bash
ruby simple_web.rb
```

The web interface will automatically open in your default browser.

## Usage

1. Enter your OpenAI API key
2. Select your scan folder (where new documents will be placed)
3. Choose your organized folder (where processed documents will go)
4. Click "Start Scanning" to begin
5. Place documents in your scan folder to process them

## Document Processing

eyeDOCtor examines documents and extracts key information such as:
- Dates
- Organization names
- Document types
- Reference numbers
- Important content

Files are then renamed and organized based on this information.

## Security

- API keys are stored locally and never transmitted
- Documents are processed on your machine
- No data is stored or sent to external servers (except OpenAI API)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 