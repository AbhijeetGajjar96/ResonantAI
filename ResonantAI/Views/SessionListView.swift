import SwiftUI

struct SessionListView: View {
    @StateObject var viewModel: SessionListViewModel
    @State private var showDatePicker = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()
    @State private var searchText: String = ""
    
    private var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return viewModel.sessions }
        let lowercased = searchText.lowercased()
        return viewModel.sessions.filter { session in
            session.title.lowercased().contains(lowercased) ||
            (session.segments.contains { $0.transcription?.lowercased().contains(lowercased) == true } ?? false)
        }
    }
    private var groupedFilteredSessions: [Date: [Session]] {
        Dictionary(grouping: filteredSessions, by: { Calendar.current.startOfDay(for: $0.createdAt) })
    }
    private var sortedDates: [Date] {
        groupedFilteredSessions.keys.sorted(by: >)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(sortedDates, id: \ .self) { date in
                    SessionSectionView(
                        date: date,
                        sessions: groupedFilteredSessions[date] ?? [],
                        sectionTitle: viewModel.sectionTitle(for: date),
                        lastSession: filteredSessions.last,
                        loadMore: viewModel.loadMore,
                        onDelete: { session in self.viewModel.deleteSession(session) }
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search title or transcription")
            .refreshable { viewModel.refresh() }
            .navigationTitle("Sessions")
            .toolbar {
                Menu("Filter") {
                    Button("All Statuses") { viewModel.setStatusFilter(nil) }
                    ForEach(TranscriptionStatus.allCases, id: \.self) { status in
                        Button(status.rawValue.capitalized) { viewModel.setStatusFilter(status) }
                    }
                    Divider()
                    Button("All Dates") { viewModel.setDateRange(nil) }
                    Button("Last 7 Days") {
                        let now = Date()
                        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
                        viewModel.setDateRange(weekAgo...now)
                    }
                    Button("Last 30 Days") {
                        let now = Date()
                        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
                        viewModel.setDateRange(monthAgo...now)
                    }
                }
                Button("Custom Date Range") { showDatePicker = true }
            }
            .sheet(isPresented: $showDatePicker) {
                VStack {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                    Button("Apply") {
                        viewModel.setDateRange(startDate...endDate)
                        showDatePicker = false
                    }
                    Button("Clear") {
                        viewModel.setDateRange(nil)
                        showDatePicker = false
                    }
                }
                .padding()
            }
        }
    }
}

private struct SessionSectionView: View {
    let date: Date
    let sessions: [Session]
    let sectionTitle: String
    let lastSession: Session?
    let loadMore: () -> Void
    let onDelete: (Session) -> Void
    @EnvironmentObject var viewModel: SessionListViewModel

    var body: some View {
        Section(header: Text(sectionTitle)) {
            ForEach(sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session).environmentObject(viewModel)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.title)
                                .font(.body)
                            Text(session.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if viewModel.isRecording(for: session) {
                                Button(action: { viewModel.stopRecording(for: session) }) {
                                    Image(systemName: "stop.circle.fill").foregroundColor(.red)
                                }
                                Button(action: { viewModel.pauseResume(for: session) }) {
                                    Image(systemName: viewModel.isPaused(for: session) ? "play.circle" : "pause.circle")
                                }
                            } else {
                                Button(action: { viewModel.startRecording(for: session) }) {
                                    Image(systemName: "mic.circle.fill").foregroundColor(.blue)
                                }
                            }
                        }
                        if viewModel.isRecording(for: session) {
                            WaveformView(levels: viewModel.audioLevels(for: session), barCount: viewModel.maxWaveformBars, barColor: .blue)
                                .frame(height: 32)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .onAppear {
                    if let last = lastSession, session.id == last.id {
                        loadMore()
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    onDelete(sessions[index])
                }
            }
        }
    }
}
