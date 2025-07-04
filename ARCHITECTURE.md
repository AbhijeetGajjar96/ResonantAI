# ResonantAI Architecture Document

## Overview
ResonantAI is a production-grade iOS audio recording and transcription app. It is designed for reliability, background operation, and scalable data management using SwiftData. The app integrates with OpenAI Whisper for backend transcription and supports Live Activities for real-time feedback.

## High-Level Architecture
- **Audio Layer:** AVAudioEngine-based recording, session management, and segmentation.
- **Transcription Layer:** Manages transcription jobs, retries, and fallback to local models.
- **Persistence Layer:** SwiftData models for sessions and segments, optimized for large datasets.
- **UI Layer:** SwiftUI views, Live Activities, and widgets for user interaction and feedback.
- **Security Layer:** Audio file encryption and secure token management.

## Audio System Design
- **Session Management:** Configures AVAudioSession for recording, handles interruptions and route changes.
- **Segmentation:** Splits audio into 30s segments, flushes buffers on background/termination.
- **Background Recording:** Uses background tasks to finish saving audio when app is backgrounded.
- **Error Handling:** Detects and reports permission issues, storage limits, and recording failures.

## Data Model Design
- **Session:** Represents a recording session, contains metadata and a list of segments.
- **Segment:** Represents a 30s audio chunk, stores file URL, transcription, status, and metadata.
- **Relationships:** Sessions have many segments; segments reference their session.
- **Performance:** Uses efficient queries, pagination, and an inverted index for search.

## Error Handling
- **Audio:** Handles permission denied, interruptions, route changes, and storage issues.
- **Transcription:** Retries with exponential backoff, falls back to local models, and marks failed jobs.
- **UI:** User-friendly alerts and Live Activities for error notification.

## Known Issues / Limitations
- Local transcription fallback is stubbed; integrate Apple Speech or Whisper for full offline support.
- Widget/Live Activity UI can be further customized.
- Large audio files may require additional cleanup strategies.

## Areas for Improvement
- Add export functionality for sessions
- Implement advanced audio processing (noise reduction, etc.)
- Expand test coverage for edge cases and performance 