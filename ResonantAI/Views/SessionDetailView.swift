import SwiftUI

struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var viewModel: SessionListViewModel
    @State private var showDatePicker = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()

    var body: some View {
        List {
            Text("Session ID: \(session.id.uuidString)")
                .font(.caption2)
                .foregroundColor(.gray)
            ForEach(session.segments) { segment in
                VStack(alignment: .leading, spacing: 8) {
                    Text(segment.transcription ?? "Transcribing...")
                        .font(.body)
                        .accessibilityLabel(segment.transcription ?? "Transcription in progress")
                    HStack {
                        Text(segment.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(segment.createdAt, style: .time)
                            .font(.caption2)
                    }
                    // Progress indicator for pending/processing
                    if segment.status == .pending || segment.status == .transcribing {
                        ProgressView()
                            .accessibilityLabel("Transcription in progress")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(session.title)
    }
}
