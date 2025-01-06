# SampleDrumConverter

A professional macOS application for batch converting WAV audio files to mono format while preserving original sample rates.

## Features

- Batch conversion of multiple files
- Preserves original sample rate
- Progress tracking for each file
- Error handling with retry option
- Keyboard shortcuts for common actions
- Context menu actions for individual files
- Direct access to converted files in Finder

## Usage

1. Add WAV files by:
   - Using the "Add WAV Files" button (⌘O)
   - Selecting multiple files in the file picker

2. Select output folder (⌘F)
3. Click "Convert to Mono" (⌘↩) to start conversion

The app will maintain the original sample rate while converting to mono format.

## Keyboard Shortcuts

- ⌘O: Add WAV files
- ⌘F: Select output folder
- ⌘↩: Start conversion
- ⌫: Remove selected file

## Requirements

- macOS 11.0 or later
- Audio files in WAV format
- Maximum file size: 100 MB per file
- Up to 50 files can be converted in one batch

## Building from Source

1. Clone the repository
2. Open the project in Xcode
3. Build and run

## License

[Your chosen license]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.