import Foundation
import SwiftData

@Model
final class Session: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Segment.session)
    var segments: [Segment]

    init(title: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.title = title
        self.segments = []
    }
} 