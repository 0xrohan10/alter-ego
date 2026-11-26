import Foundation

public struct JobStore: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func file(_ id: UUID, _ name: String) -> URL { directory(id).appendingPathComponent(name) }
    public func create(_ job: GuestJob, selfie: Data) throws {
        let dir = directory(job.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try selfie.write(to: file(job.id, "selfie.jpg"), options: .atomic)
            try save(job)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }
    public func save(_ job: GuestJob) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(job).write(to: file(job.id, "job.json"), options: .atomic)
    }
    public func load() throws -> (jobs: [GuestJob], warnings: [String]) {
        var jobs: [GuestJob] = []; var warnings: [String] = []
        for dir in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            guard let id = UUID(uuidString: dir.lastPathComponent) else { continue }
            do {
                var job = try JSONDecoder().decode(GuestJob.self, from: Data(contentsOf: file(id, "job.json")))
                guard job.id == id else { throw AlterEgoError.invalid("Job ID mismatch") }
                let previous = job
                job.recover(cardExists: FileManager.default.fileExists(atPath: file(id, "card.jpg").path))
                if job != previous { try save(job) }
                if job.generation == .ready { try? FileManager.default.removeItem(at: file(id, "selfie.jpg")) }
                jobs.append(job)
            } catch { warnings.append("Could not recover \(id.uuidString.prefix(8)): \(error.localizedDescription)") }
        }
        return (jobs.sorted { $0.number < $1.number }, warnings)
    }
}
