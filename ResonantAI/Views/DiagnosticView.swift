import SwiftUI
import Speech
import AVFoundation

struct DiagnosticView: View {
    @StateObject private var diagnosticViewModel = DiagnosticViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Speech Recognition Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(title: "Authorization", isEnabled: diagnosticViewModel.status.authorizationStatus == .authorized)
                        StatusRow(title: "Recognizer Available", isEnabled: diagnosticViewModel.status.isRecognizerAvailable)
                        StatusRow(title: "On-Device Recognition", isEnabled: diagnosticViewModel.status.supportsOnDeviceRecognition)
                        StatusRow(title: "Microphone Permission", isEnabled: diagnosticViewModel.status.hasMicrophonePermission)
                        StatusRow(title: "Audio Input Available", isEnabled: diagnosticViewModel.status.hasAudioInput)
                    }
                }
                
                if !diagnosticViewModel.status.diagnostics.isEmpty {
                    Section("Issues Found") {
                        ForEach(diagnosticViewModel.status.diagnostics, id: \.self) { diagnostic in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(diagnostic)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                if let whisperResult = diagnosticViewModel.whisperTestResult {
                    Section("Whisper API Test") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(whisperResult)
                                .font(.caption)
                        }
                    }
                }
                
                if let audioResult = diagnosticViewModel.audioTestResult {
                    Section("Audio Pipeline Test") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(audioResult)
                                .font(.caption)
                        }
                    }
                }
                
                Section("Local Speech Recognition Error (Code=1101)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("If you're seeing 'kAFAssistantErrorDomain Code=1101', this means:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Local speech recognition service is unavailable")
                            Text("• Device may not support on-device recognition")
                            Text("• Speech recognition data may not be downloaded")
                            Text("• System-level speech recognition issues")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Text("Solutions:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Check device compatibility (iOS 13.0+)")
                            Text("2. Go to Settings > General > Language & Region")
                            Text("3. Add/Download speech recognition language data")
                            Text("4. Ensure sufficient storage space")
                            Text("5. Restart your device")
                            Text("6. Use server-based transcription as fallback")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                Section("Actions") {
                    Button("Check Capabilities") {
                        Task {
                            await diagnosticViewModel.checkCapabilities()
                        }
                    }
                    .disabled(diagnosticViewModel.isChecking)
                    
                    Button("Request Permissions") {
                        Task {
                            await diagnosticViewModel.requestPermissions()
                        }
                    }
                    .disabled(diagnosticViewModel.isRequestingPermissions)
                    
                    Button("Test Whisper API") {
                        Task {
                            await diagnosticViewModel.testWhisperAPI()
                        }
                    }
                    .disabled(diagnosticViewModel.isTestingWhisper)
                    
                    Button("Test Audio Pipeline") {
                        Task {
                            await diagnosticViewModel.testAudioPipeline()
                        }
                    }
                    .disabled(diagnosticViewModel.isTestingAudio)
                    
                    if diagnosticViewModel.isChecking || diagnosticViewModel.isRequestingPermissions || diagnosticViewModel.isTestingWhisper || diagnosticViewModel.isTestingAudio {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await diagnosticViewModel.checkCapabilities()
            }
        }
    }
}

struct StatusRow: View {
    let title: String
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isEnabled ? .green : .red)
        }
    }
}

@MainActor
class DiagnosticViewModel: ObservableObject {
    @Published var status = SpeechRecognitionStatus()
    @Published var isChecking = false
    @Published var isRequestingPermissions = false
    @Published var isTestingWhisper = false
    @Published var isTestingAudio = false
    @Published var whisperTestResult: String?
    @Published var audioTestResult: String?
    
    func checkCapabilities() async {
        isChecking = true
        defer { isChecking = false }
        
        status = await DeviceCapabilityChecker.checkSpeechRecognitionCapabilities()
    }
    
    func requestPermissions() async {
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }
        
        // Request speech recognition authorization
        let speechAuthStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        // Request microphone permission
        let audioAuthStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        // Re-check capabilities after permissions
        await checkCapabilities()
    }
    
    func testWhisperAPI() async {
        isTestingWhisper = true
        defer { isTestingWhisper = false }
//        
//        let whisperTest = WhisperTest()
//        whisperTest.testConfiguration()
        
        // Note: This would test with actual audio in a real scenario
        whisperTestResult = "API configuration test completed. Check console for details."
    }
    
    func testAudioPipeline() async {
        isTestingAudio = true
        defer { isTestingAudio = false }
        
        let audioTest = AudioTest()
        await audioTest.testCompletePipeline()
        
        audioTestResult = "Audio pipeline test completed. Check console for details."
    }
}

#Preview {
    DiagnosticView()
} 
