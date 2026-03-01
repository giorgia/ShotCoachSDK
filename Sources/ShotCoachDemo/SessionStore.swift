import Foundation
import ShotCoachCore

/// In-memory store for every photo captured during this demo session.
///
/// In a production app you'd persist entries with SwiftData, CoreData, or a
/// cloud backend. For the demo, in-memory is enough to power the gallery tab.
@MainActor
final class SessionStore: ObservableObject {

    // MARK: - Entry

    /// A single captured photo bundled with its category context.
    struct Entry: Identifiable {
        let id = UUID()
        let photo: SCPhoto
        let categoryName: String
        let capturedAt: Date
    }

    // MARK: - State

    @Published private(set) var entries: [Entry] = []

    // MARK: - Mutations

    func add(_ photo: SCPhoto, categoryName: String) {
        entries.append(Entry(photo: photo, categoryName: categoryName, capturedAt: Date()))
    }

    func clear() {
        entries.removeAll()
    }
}
