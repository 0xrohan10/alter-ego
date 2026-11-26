import Foundation

public enum GenerationState: String, Codable, Sendable { case queued, generating, ready, failed, cancelled }
public enum PrintState: String, Codable, Sendable { case waiting, queued, submitting, submitted, needsReview, failed, printed, cancelled }

public struct CharacterConcept: Codable, Sendable, Equatable {
    public let title: String
    public let imagePrompt: String
    public init(title: String, imagePrompt: String) { self.title = title; self.imagePrompt = imagePrompt }
}

public struct GuestJob: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let number: Int
    public let name: String
    public let fact: String
    public let createdAt: Date
    public var generation: GenerationState = .queued
    public var printing: PrintState = .waiting
    public var generationAttempts = 0
    public var printAttempts = 0
    public var readyAt: Date?
    public var printQueuedAt: Date?
    public var generationError: String?
    public var printError: String?
    public init(id: UUID = UUID(), number: Int, name: String, fact: String, createdAt: Date = Date()) {
        self.id = id; self.number = number; self.name = name; self.fact = fact; self.createdAt = createdAt
    }
    public mutating func recover(cardExists: Bool) {
        if generation == .generating {
            if cardExists { generation = .ready; printing = .queued; readyAt = readyAt ?? Date(); printQueuedAt = printQueuedAt ?? readyAt }
            else { generation = .failed; generationError = "Interrupted. Retry to resume from saved artifacts." }
        }
        if printing == .submitting {
            printing = .needsReview; printError = "Interrupted print; check the printer before reprinting."
        }
        if generation == .ready && !cardExists {
            generation = .failed; printing = .waiting; generationError = "Card file missing. Retry generation."
        }
    }
}

public enum AlterEgoError: LocalizedError {
    case invalid(String), api(Int, String), missingOutput, unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .unsupported(let s): return s
        case .api(let code, let message): return "API \(code): \(message)"
        case .missingOutput: return "The model returned no usable output."
        }
    }
}

public struct PipelineConfig: Sendable {
    public var textModel = "gpt-6-luna"
    public var imageModel = "gpt-image-2.6-flare"
    public var quality = "medium"
    public var houseStyle = """
    Create a collectible editorial character portrait for a fictional retro-futurist Christmas expedition. Use sophisticated mid-century science-fiction book-cover illustration, rich deep midnight blue, warm ivory, crimson and burnished gold, tactile printed texture, dramatic but flattering lighting, and crisp graphic shapes. Preserve the person's recognizable face, skin tone, age, hair, glasses and facial hair from the reference selfie. Transform their outfit and surroundings to express the supplied character concept. Make the interpretation clever, warm and specific, never cruel or humiliating. Frame the subject waist-up in a vertical 2:3 composition, face prominent near the upper center with generous breathing room. Use a coherent, detailed but uncluttered background. Subtle winter or festive motifs; no mandatory Santa hat. No letters, numbers, typography, logos, card frames or borders. The artwork is a standalone illustration that will be placed in a separately designed card.
    """
    public init() {}
}

public enum QueuePolicy {
    public static func nextGeneration(_ jobs: [GuestJob], active: Int, limit: Int = 3) -> [GuestJob] {
        Array(jobs.filter { $0.generation == .queued }.sorted { $0.number < $1.number }.prefix(max(0, limit - active)))
    }
    public static func nextPrint(_ jobs: [GuestJob]) -> GuestJob? {
        jobs.filter { $0.generation == .ready && $0.printing == .queued }.sorted {
            let a = $0.printQueuedAt ?? $0.readyAt ?? $0.createdAt
            let b = $1.printQueuedAt ?? $1.readyAt ?? $1.createdAt
            return a == b ? $0.number < $1.number : a < b
        }.first
    }
}
