import Foundation

// DSA: Inverted Index for fast full-text search
struct InvertedIndex {
    private(set) var index: [String: Set<UUID>] = [:]

    // Build index from segments
    mutating func build(from segments: [Segment]) {
        index.removeAll()
        for segment in segments {
            guard let text = segment.transcription else { continue }
            let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
            for word in words {
                index[String(word), default: []].insert(segment.id)
            }
        }
    }

    // Search for segment IDs containing the word
    func search(_ word: String) -> Set<UUID> {
        return index[word.lowercased()] ?? []
    }
} 