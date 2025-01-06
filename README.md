# SampleDrumConverter

A simple macOS application for converting WAV audio files to a standardized format commonly used in drum sample libraries.

## Features

- Converts WAV files to:
  - Mono (single channel)
  - 48 kHz sample rate
  - 16-bit resolution
- Simple drag-and-drop interface
- Progress indicator during conversion
- Audio output test function
- Support for files up to 100 MB

## Usage

1. Launch the application
2. Click "Select input WAV file" to choose your source audio file
3. Click "Convert to mono, 48kHz, 16-bit WAV" to start the conversion
4. Choose where to save the converted file
5. Wait for the conversion to complete

The converted file will maintain the original filename with "Mono" added to indicate the conversion.

## Technical Details

The application uses:
- AudioKit for audio processing
- ExtAudioFile API for high-quality audio conversion
- SwiftUI for the user interface

## Requirements

- macOS 11.0 or later
- Audio files in WAV format
- Maximum file size: 100 MB

## Building from Source

1. Clone the repository
2. Open the project in Xcode
3. Build and run

## License

[Your chosen license]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.