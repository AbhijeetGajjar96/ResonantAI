import SwiftUI
import SwiftData
import Network

struct RecordingViewContainer: View {
    @Query(sort: \Session.createdAt, order: .reverse) var sessions: [Session]
    @StateObject var viewModel = RecordingViewModel(manager: RecordingManager(fileManager: EncryptedFileManager()))
    @StateObject var networkStatus = NetworkStatusViewModel()

    var body: some View {
        NavigationView {
            RecordingView(viewModel: viewModel, sessions: sessions, networkStatus: networkStatus)
        }
    }
}

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: RecordingViewModel
    var sessions: [Session]
    @ObservedObject var networkStatus: NetworkStatusViewModel
    @State private var session: Session?
    @State private var showMicAlert = false
    @State private var showSpeechAlert = false
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 24) {
            // Header with diagnostics button
            HStack {
                Text(viewModel.isRecording ? "Recording..." : "Ready")
                    .font(.headline)
                    .accessibilityLabel(viewModel.isRecording ? "Recording in progress" : "Ready to record")
                
                Spacer()
                
                // Network indicator (bars + text)
                HStack(spacing: 4) {
                    NetworkStrengthView(status: networkStatus.status, interfaceType: networkStatus.interfaceType)
                    Text(networkStatus.status == .satisfied ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(networkStatus.status == .satisfied ? .green : .red)
                }
                
                Button(action: {
                    showDiagnostics = true
                }) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Open diagnostics")
            }
            HStack(spacing: 32) {
                Button(action: {
                    if !viewModel.isRecording {
                        // Create a random session title
                        let randomTitle = "Session-" + UUID().uuidString.prefix(8)
                        let newSession = Session(title: String(randomTitle))
                        modelContext.insert(newSession)
                        try? modelContext.save()
                        session = newSession
                        viewModel.manager.setModelContext(modelContext)
                        viewModel.manager.setCurrentSession(newSession)
                        viewModel.toggleRecording()
                    } else {
                        viewModel.toggleRecording()
                        session = nil
                    }
                }) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(viewModel.isRecording ? .red : .blue)
                        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                }
                if viewModel.isRecording {
                    Button(action: { viewModel.pauseResume() }) {
                        Image(systemName: viewModel.isPaused ? "play.circle" : "pause.circle")
                            .font(.system(size: 48))
                            .accessibilityLabel(viewModel.isPaused ? "Resume recording" : "Pause recording")
                    }
                }
            }
            
            // Level meter (optional, simple bar)
            WaveformView(levels: viewModel.audioLevels, barCount: viewModel.maxWaveformBars, barColor: .blue)
                .padding(.horizontal)
                .accessibilityLabel("Audio waveform")
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .accessibilityLabel("Error: \(error.localizedDescription)")
            }

            // List of previous sessions
            Text("Previous Sessions")
                .font(.headline)
                .padding(.top)
            List {
                ForEach(sessions) { s in
                    NavigationLink(destination: SessionDetailView(session: s)) {
                        VStack(alignment: .leading) {
                            Text(s.title)
                                .font(.body)
                            Text(s.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .alert("Microphone Permission Denied", isPresented: $showMicAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable microphone access in Settings to record audio.")
        }
        .alert("Speech Recognition Permission Denied", isPresented: $showSpeechAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable speech recognition access in Settings to transcribe audio.")
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticView()
        }
    }
}

struct WaveformView: View {
    let levels: [Float]
    let barCount: Int
    let barColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let level = i < levels.count ? levels[i] : 0
                Capsule()
                    .fill(barColor)
                    .frame(width: 4, height: max(8, CGFloat(level) * 60))
            }
        }
        .frame(height: 64)
        .animation(.linear(duration: 0.1), value: levels)
    }
}

// NetworkStrengthView: shows bars based on status/interface
struct NetworkStrengthView: View {
    let status: NWPath.Status
    let interfaceType: NWInterface.InterfaceType?
    var barCount: Int {
        guard status == .satisfied else { return 0 }
        switch interfaceType {
        case .wifi: return 3
        case .cellular: return 2
        case .wiredEthernet: return 3
        default: return 1
        }
    }
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(i < barCount ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(6 + i * 6))
            }
        }
        .frame(width: 14, height: 18)
    }
} 
