//import Foundation
//import AVFoundation
//
//// MARK: - Whisper API Test Utility
//class WhisperTest {
//    private let apiClient = TranscriptionAPIClient()
//    
//    /// Test the OpenAI Whisper API with a sample audio file
//    func testWhisperAPI() async {
//        print("[WhisperTest] Starting Whisper API test...")
//        
//        // Validate API configuration
//        guard APIConfig.isValidAPIKey() else {
//            print("[WhisperTest] ❌ Invalid API key")
//            return
//        }
//        
//        print("[WhisperTest] ✅ API key is valid")
//        
//        // Create a simple test audio file (you would replace this with actual audio)
//        guard let testAudioURL = createTestAudioFile() else {
//            print("[WhisperTest] ❌ Failed to create test audio file")
//            return
//        }
//        
//        defer {
//            // Clean up test file
//            try? FileManager.default.removeItem(at: testAudioURL)
//        }
//        
//        do {
//            print("[WhisperTest] 🎤 Testing Whisper transcription...")
//            let transcription = try await apiClient.transcribe(url: testAudioURL)
//            print("[WhisperTest] ✅ Transcription successful: \(transcription)")
//        } catch {
//            print("[WhisperTest] ❌ Transcription failed: \(error)")
//            
//            // Test local fallback
//            do {
//                print("[WhisperTest] 🔄 Testing local fallback...")
//                let localTranscription = try await apiClient.transcribeLocally(url: testAudioURL)
//                print("[WhisperTest] ✅ Local transcription successful: \(localTranscription)")
//            } catch {
//                print("[WhisperTest] ❌ Local transcription also failed: \(error)")
//            }
//        }
//    }
//    
//    /// Create a simple test audio file for testing
//    private func createTestAudioFile() -> URL? {
//        // This is a placeholder - in a real app, you'd use actual audio
//        // For testing purposes, we'll create a minimal audio file
//        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.m4a")
//        
//        // Note: This is a simplified test - in practice you'd want to use actual audio
//        // For now, we'll just create an empty file to test the API structure
//        do {
//            try Data().write(to: testURL)
//            return testURL
//        } catch {
//            return nil
//        }
//    }
//    
//    /// Test API configuration
//    func testConfiguration() {
//        print("[WhisperTest] Testing API configuration...")
//        print("API Key valid: \(APIConfig.isValidAPIKey())")
//        print("Whisper API URL: \(APIConfig.whisperAPIURL)")
//        print("Max file size: \(APIConfig.maxAudioFileSizeMB)MB")
//        print("Supported formats: \(APIConfig.supportedAudioFormats.joined(separator: ", "))")
//    }
//} 
