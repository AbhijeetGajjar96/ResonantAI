import Foundation
import Combine
import SwiftData
import Network
import ActivityKit
import AVFoundation

struct TranscriptionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var progress: Double
    }
    var segmentID: UUID
}

final class TranscriptionManager: ObservableObject {
    struct TranscriptionJob {
        let segmentURL: URL
        let segmentID: UUID
        var retryCount: Int = 0
        var contextualStrings: [String]? = nil // For contextual vocabulary
    }

    @Published var jobs: [TranscriptionJob] = []
    private var jobQueue = DispatchQueue(label: "transcriptionQueue", qos: .background)
    private var offlineQueue: [TranscriptionJob] = []
    private var isProcessing = false
    private let apiClient: TranscriptionAPIClient
    private let localTranscriber: LocalTranscriber
    private let fileManager: EncryptedFileManager
    private let maxRetries = 5
    private var modelContext: ModelContext?
    private var monitor: NWPathMonitor?
    private var transcriptionActivities: [UUID: Activity<TranscriptionActivityAttributes>] = [:]
    private let concurrentJobs = 2
    private let semaphore = DispatchSemaphore(value: 2)

    // DSA: Queue for jobs, exponential backoff, fallback

    init(apiClient: TranscriptionAPIClient, localTranscriber: LocalTranscriber, fileManager: EncryptedFileManager) {
        self.apiClient = apiClient
        self.localTranscriber = localTranscriber
        self.fileManager = fileManager
        NotificationCenter.default.addObserver(self, selector: #selector(handleSegment(_:)), name: .didFinishSegment, object: nil)
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    @objc private func handleSegment(_ notification: Notification) {
        guard let segmentID = notification.object as? UUID else { return }
        print("[TranscriptionManager] handleSegment: Received segment ID: \(segmentID)")
        
        // Find the segment in the database to get its URL
        guard let context = modelContext else {
            print("[TranscriptionManager] No model context available")
            return
        }
        
        // Fetch all segments and find the one with matching ID
        let fetchDescriptor = FetchDescriptor<Segment>()
        let segments = try? context.fetch(fetchDescriptor)
        guard let segment = segments?.first(where: { $0.id == segmentID }) else {
            print("[TranscriptionManager] Segment not found for ID: \(segmentID)")
            return
        }
        
        let job = TranscriptionJob(segmentURL: segment.audioFileURL, segmentID: segmentID)
        enqueue(job)
    }

    func enqueue(_ job: TranscriptionJob) {
        print("[TranscriptionManager] enqueue: Adding job for segmentID: \(job.segmentID)")
        jobQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.jobs.append(job)
                self?.processNext()
            }
        }
    }

    private func processNext() {
        print("[TranscriptionManager] processNext: jobs count = \(jobs.count), isProcessing = \(isProcessing)")
        guard jobs.count > 0 else { return }
        // Start up to concurrentJobs in parallel
        let runningJobs = jobs.prefix(concurrentJobs)
        for job in runningJobs {
            process(job)
        }
    }

    private func process(_ job: TranscriptionJob) {
        semaphore.wait()
        print("[TranscriptionManager] Processing job for segment ID: \(job.segmentID)")
        let startTime = Date()
        
        // Verify segment exists in database
        guard let context = modelContext else {
            print("[TranscriptionManager] No model context available")
            self.fail(job: job)
            return
        }
        
        // Fetch all segments and find the one with matching ID
        let fetchDescriptor = FetchDescriptor<Segment>()
        let segments = try? context.fetch(fetchDescriptor)
        guard let segment = segments?.first(where: { $0.id == job.segmentID }) else {
            print("[TranscriptionManager] Segment not found in database for ID: \(job.segmentID)")
            self.fail(job: job)
            return
        }
        
        print("[TranscriptionManager] Found segment: \(segment.audioFileURL.lastPathComponent)")
        
        // Decrypt audio file if needed and print file info
        let decryptedURL: URL
        do {
            decryptedURL = try self.fileManager.decryptedTempURL(for: job.segmentURL)
            printAudioFileInfo(url: decryptedURL)
            
            // Verify the decrypted file exists and has content
            let fileSize = try? decryptedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize! > 0 else {
                print("[TranscriptionManager] Decrypted file is empty")
                self.fail(job: job)
                return
            }
            print("[TranscriptionManager] Decrypted file size: \(fileSize) bytes")
        } catch {
            print("[TranscriptionManager] Failed to decrypt audio file: \(error)")
            self.fail(job: job)
            return
        }
        
        Task {
            defer {
                print("[TranscriptionManager] Job for segment \(job.segmentID) took \(Date().timeIntervalSince(startTime)) seconds")
                self.semaphore.signal()
            }
            do {
                // Try local Apple transcription (now the only method)
                print("[TranscriptionManager] Attempting Apple SFSpeechRecognizer transcription...")
                let transcription = try await apiClient.transcribe(url: decryptedURL, contextualStrings: job.contextualStrings)
                // Clean up temp file
                try? FileManager.default.removeItem(at: decryptedURL)
                await MainActor.run {
                    self.complete(job: job, transcription: transcription, source: "Apple Speech")
                }
            } catch {
                // Clean up temp file
                try? FileManager.default.removeItem(at: decryptedURL)
                print("[TranscriptionManager] Local transcription failed: \(error)")
                // Fallback to localTranscriber if available
                do {
                    print("[TranscriptionManager] Attempting offline fallback transcription...")
                    let fallbackTranscription = try await localTranscriber.transcribeAudioFile(at: job.segmentURL)
                    await MainActor.run {
                        self.complete(job: job, transcription: fallbackTranscription, source: "Local Fallback")
                    }
                } catch {
                    print("[TranscriptionManager] Local fallback transcription also failed: \(error)")
                    await MainActor.run {
                        self.fail(job: job)
                    }
                }
            }
            await MainActor.run {
                self.jobs.removeAll { $0.segmentID == job.segmentID }
                self.isProcessing = false
                self.processNext()
            }
        }
    }

    private func printAudioFileInfo(url: URL) {
        let asset = AVURLAsset(url: url)
        print("Audio file info:")
        print("- Duration: \(CMTimeGetSeconds(asset.duration)) seconds")
        print("- File size: \(String(describing: try? Data(contentsOf: url).count)) bytes")
        if let format = asset.tracks(withMediaType: .audio).first?.formatDescriptions.first {
            print("- Format: \(format)")
        }
    }

    private func complete(job: TranscriptionJob, transcription: String, source: String = "Unknown") {
        guard let context = modelContext else { print("[TranscriptionManager] complete: No modelContext"); return }
        let segmentID = job.segmentID
        // Fetch all segments and find the one with matching ID
        let fetchDescriptor = FetchDescriptor<Segment>()
        let segments = try? context.fetch(fetchDescriptor)
        print("[TranscriptionManager] complete: Fetching segment with id \(segmentID)")
        if let segment = segments?.first(where: { $0.id == segmentID }) {
            print("[TranscriptionManager] complete: Found segment, updating transcription and status (source: \(source))")
            segment.transcription = transcription
            segment.status = {
                switch source {
                case "OpenAI Whisper":
                    return TranscriptionStatus.whisperAPI
                case "Local Fallback":
                    return TranscriptionStatus.offlineFallback
                default:
                    return TranscriptionStatus.completed
                }
            }()
            try? context.save()
        } else {
            print("[TranscriptionManager] complete: Segment not found for id \(segmentID)")
        }
    }

    private func fail(job: TranscriptionJob) {
        guard let context = modelContext else { print("[TranscriptionManager] fail: No modelContext"); return }
        let segmentID = job.segmentID
        // Fetch all segments and find the one with matching ID
        let fetchDescriptor = FetchDescriptor<Segment>()
        let segments = try? context.fetch(fetchDescriptor)
        print("[TranscriptionManager] fail: Fetching segment with id \(segmentID)")
        if let segment = segments?.first(where: { $0.id == segmentID }) {
            print("[TranscriptionManager] fail: Found segment, updating status to failed")
            segment.status = TranscriptionStatus.failed
            try? context.save()
        } else {
            print("[TranscriptionManager] fail: Segment not found for id \(segmentID)")
        }
    }

    func startNetworkMonitor() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                // Retry failed/queued jobs
                self?.retryQueuedJobs()
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor?.start(queue: queue)
    }

    func retryQueuedJobs() {
        // Re-enqueue jobs with .failed or .queued status
        guard let context = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<Segment>()
        let segments = try? context.fetch(fetchDescriptor)
        let failedSegments = segments?.filter { $0.status == .failed || $0.status == .queued } ?? []
        for segment in failedSegments {
            // Avoid infinite retries
            let retryCount = jobs.first(where: { $0.segmentID == segment.id })?.retryCount ?? 0
            if retryCount < maxRetries {
                let job = TranscriptionJob(segmentURL: segment.audioFileURL, segmentID: segment.id, retryCount: retryCount + 1)
                enqueue(job)
            } else {
                print("[TranscriptionManager] Max retries reached for segment \(segment.id)")
            }
        }
    }

    private func updateTranscriptionActivity(_ segmentID: UUID, status: String, progress: Double) {
        if let activity = transcriptionActivities[segmentID] {
            Task {
                await activity.update(using: .init(status: status, progress: progress))
            }
        }
    }

    private func endTranscriptionActivity(_ segmentID: UUID) {
        if let activity = transcriptionActivities[segmentID] {
            Task {
                await activity.end(dismissalPolicy: .immediate)
            }
            transcriptionActivities.removeValue(forKey: segmentID)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Determines if an error is retryable (network issues, temporary API errors, etc.)
    private func isRetryableError(_ error: Error) -> Bool {
        // Check for network-related errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        
        // Check for API errors that might be temporary
        if let transcriptionError = error as? TranscriptionAPIClient.TranscriptionError {
            switch transcriptionError {
            case .networkError, .apiError:
                return true
            case .permissionDenied, .notAvailable, .recognizerNotAvailable, .parsingError, .conversionError:
                return false
            }
        }
        
        // Default to not retryable for unknown errors
        return false
    }
} 
