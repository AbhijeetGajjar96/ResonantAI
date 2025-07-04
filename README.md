# ResonantAI

A robust iOS audio recording and transcription app built with SwiftUI, AVAudioEngine, ActivityKit, and SwiftData. Designed for real-world reliability, background recording, and scalable data management.

## Features
- Production-grade audio recording with AVAudioEngine
- Handles audio interruptions, route changes, and background recording
- Automatic segmentation and backend transcription (OpenAI Whisper)
- Exponential backoff, offline queuing, and local fallback for transcription
- Secure audio file encryption and API token management
- Scalable SwiftData models for sessions and segments
- Modern SwiftUI UI: recording controls, session list, detail view
- Live Activities and widget support for real-time updates
- Full accessibility and VoiceOver support
- Robust error handling for all edge cases

## Setup Instructions
1. Clone the repo: `git clone <your-repo-url>`
2. Open `ResonantAI.xcodeproj` in Xcode 15+
3. Add your OpenAI API key in `ResonantAIApp.swift` or via the in-app settings
4. Enable Background Modes (Audio) in Signing & Capabilities
5. Build and run on a real device (Live Activities require a device)

## Architecture Overview
- **Audio System:** `RecordingManager` uses AVAudioEngine, handles session, interruptions, and route changes. Segments audio for transcription.
- **Transcription:** `TranscriptionManager` manages a queue, retries, and fallback. Integrates with OpenAI Whisper and local models.
- **Data Model:** SwiftData models for `Session` and `Segment` with relationships and performance optimizations.
- **UI:** SwiftUI views for recording, session list, and details. Live Activities and widgets for real-time feedback.
- **Security:** Audio files encrypted at rest, API tokens in Keychain.
- **Error Handling:** Comprehensive error management and user alerts.

## Usage
- Tap the mic to start/stop recording
- View and search sessions in the session list
- Tap a session for segment details and transcription status
- Watch real-time progress in the Dynamic Island/Lock Screen

## Testing
- Unit, integration, and performance tests included (see `Tests/`)
- To run tests: Product > Test in Xcode

## Contact
For questions or feedback, open an issue or contact [Your Name] at [your.email@example.com]. 