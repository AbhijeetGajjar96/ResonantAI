import Foundation
import Combine
import SwiftData

final class SessionListViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var searchText: String = ""
    @Published var groupedSessions: [Date: [Session]] = [:]
    @Published var hasMore: Bool = true
    @Published var selectedStatus: TranscriptionStatus? = nil
    @Published var dateRange: ClosedRange<Date>? = nil
    @Published var sessionRecordingState: [UUID: (isRecording: Bool, isPaused: Bool, audioLevels: [Float])] = [:]
    private var cancellables = Set<AnyCancellable>()
    // DSA: Inverted index for fast search
    private var invertedIndex: [String: Set<UUID>] = [:]
    private var fetchOffset: Int = 0
    private let fetchLimit: Int = 20
    private var context: ModelContext? = nil
    private var sessionManagers: [UUID: RecordingManager] = [:]
    private var sessionCancellables: [UUID: Set<AnyCancellable>] = [:]
    let maxWaveformBars = 30

    init(context: ModelContext? = nil) {
        self.context = context
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in self?.filterSessions(text) }
            .store(in: &cancellables)
        $selectedStatus
            .sink { [weak self] _ in self?.filterSessions(self?.searchText ?? "") }
            .store(in: &cancellables)
        $dateRange
            .sink { [weak self] _ in self?.filterSessions(self?.searchText ?? "") }
            .store(in: &cancellables)
    }

    func setContext(_ context: ModelContext) {
        self.context = context
    }

    func refresh() {
        guard let context = context else { return }
        var fetchDescriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\Session.createdAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = fetchLimit
        fetchDescriptor.fetchOffset = fetchOffset
        do {
            let fetched = try context.fetch(fetchDescriptor)
            if fetchOffset == 0 {
                sessions = fetched
            } else {
                sessions.append(contentsOf: fetched)
            }
            hasMore = fetched.count == fetchLimit
            buildInvertedIndex()
            groupSessionsByDate()
        } catch {
            print("Failed to fetch sessions: \(error)")
        }
    }

    func loadMore() {
        guard hasMore else { return }
        fetchOffset += fetchLimit
        refresh()
    }

    private func groupSessionsByDate() {
        let calendar = Calendar.current
        groupedSessions = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.createdAt)
        }
    }

    // Build inverted index from session titles and segment transcriptions
    private func buildInvertedIndex() {
        invertedIndex.removeAll()
        for session in sessions {
            // Index session title
            let titleWords = session.title.lowercased().split { !$0.isLetter && !$0.isNumber }
            for word in titleWords {
                invertedIndex[String(word), default: []].insert(session.id)
            }
            // Index segment transcriptions
            for segment in session.segments {
                if let text = segment.transcription {
                    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
                    for word in words {
                        invertedIndex[String(word), default: []].insert(session.id)
                    }
                }
            }
        }
    }

    func filterSessions(_ text: String) {
        var filtered: [Session]
        if text.isEmpty {
            filtered = sessions
        } else {
            // Full-text search using inverted index
            let searchWords = text.lowercased().split { !$0.isLetter && !$0.isNumber }
            var matchingSessionIDs: Set<UUID>?
            for word in searchWords {
                let ids = invertedIndex[String(word)] ?? []
                if let current = matchingSessionIDs {
                    matchingSessionIDs = current.intersection(ids)
                } else {
                    matchingSessionIDs = ids
                }
            }
            if let ids = matchingSessionIDs, !ids.isEmpty {
                filtered = sessions.filter { ids.contains($0.id) }
            } else {
                filtered = []
            }
        }
        // Filter by status
        if let status = selectedStatus {
            filtered = filtered.filter { $0.segments.contains(where: { $0.status == status }) }
        }
        // Filter by date range
        if let range = dateRange {
            filtered = filtered.filter { range.contains($0.createdAt) }
        }
        // Group for display
        let calendar = Calendar.current
        groupedSessions = Dictionary(grouping: filtered) { session in
            calendar.startOfDay(for: session.createdAt)
        }
    }

    // Public methods to set filters
    func setStatusFilter(_ status: TranscriptionStatus?) {
        selectedStatus = status
    }
    func setDateRange(_ range: ClosedRange<Date>?) {
        dateRange = range
    }

    func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    func deleteSession(_ session: Session) {
        guard let context = context else { return }
        context.delete(session)
        try? context.save()
        refresh()
    }

    // Start recording for a session
    func startRecording(for session: Session) {
        let manager = RecordingManager(fileManager: EncryptedFileManager())
        sessionManagers[session.id] = manager
        var cancellables = Set<AnyCancellable>()
        manager.$isRecording.sink { [weak self] isRec in
            self?.sessionRecordingState[session.id, default: (false, false, [])].isRecording = isRec
        }.store(in: &cancellables)
        manager.$audioLevel.sink { [weak self] level in
            var state = self?.sessionRecordingState[session.id] ?? (false, false, [])
            state.audioLevels.append(level)
            if state.audioLevels.count > self?.maxWaveformBars ?? 30 {
                state.audioLevels.removeFirst(state.audioLevels.count - (self?.maxWaveformBars ?? 30))
            }
            self?.sessionRecordingState[session.id] = state
        }.store(in: &cancellables)
        sessionCancellables[session.id] = cancellables
        manager.setCurrentSession(session)
        manager.startRecording()
        sessionRecordingState[session.id] = (true, false, [])
    }
    // Stop recording for a session
    func stopRecording(for session: Session) {
        if let manager = sessionManagers[session.id] {
            manager.stopRecording()
            sessionRecordingState[session.id]?.isRecording = false
            sessionRecordingState[session.id]?.isPaused = false
            sessionRecordingState[session.id]?.audioLevels = []
            sessionManagers[session.id] = nil
            sessionCancellables[session.id] = nil
        }
    }
    // Pause/resume recording for a session
    func pauseResume(for session: Session) {
        guard let manager = sessionManagers[session.id] else { return }
        let isPaused = sessionRecordingState[session.id]?.isPaused ?? false
        if isPaused {
            manager.resumeRecording()
        } else {
            manager.pauseRecording()
        }
        sessionRecordingState[session.id]?.isPaused.toggle()
    }
    // Accessors for UI
    func isRecording(for session: Session) -> Bool {
        sessionRecordingState[session.id]?.isRecording ?? false
    }
    func isPaused(for session: Session) -> Bool {
        sessionRecordingState[session.id]?.isPaused ?? false
    }
    func audioLevels(for session: Session) -> [Float] {
        sessionRecordingState[session.id]?.audioLevels ?? []
    }
} 