import Foundation

public struct PipelineMetrics: Codable, Sendable {
    public var conceptSeconds: Double = 0
    public var imageSeconds: Double = 0
    public var renderingSeconds: Double = 0
    public var totalSeconds: Double = 0
    public var textModel: String
    public var imageModel: String
    public var quality: String
    public var demo: Bool
}

public struct CharacterPipeline: Sendable {
    public let client: OpenAIClient
    public let config: PipelineConfig
    public init(client: OpenAIClient, config: PipelineConfig = .init()) { self.client = client; self.config = config }
    public func run(name: String, fact: String, number: Int, directory: URL, demo: Bool = false) async throws -> PipelineMetrics {
        let clock = Date(); let fm = FileManager.default
        var metrics = PipelineMetrics(textModel: config.textModel, imageModel: config.imageModel, quality: config.quality, demo: demo)
        let conceptURL = directory.appendingPathComponent("concept.json")
        let avatarURL = directory.appendingPathComponent("avatar.jpg")
        let selfieURL = directory.appendingPathComponent("selfie.jpg")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let concept: CharacterConcept
        let t1 = Date()
        if fm.fileExists(atPath: conceptURL.path) { concept = try JSONDecoder().decode(CharacterConcept.self, from: Data(contentsOf: conceptURL)) }
        else {
            if demo { concept = .init(title: "The Celestial Explorer", imagePrompt: "An adventurous festive space explorer.") }
            else { concept = try await client.concept(fact: fact, model: config.textModel) }
            try encoder.encode(concept).write(to: conceptURL, options: .atomic)
        }
        metrics.conceptSeconds = Date().timeIntervalSince(t1)
        let prompt = config.houseStyle + "\nCharacter concept: " + concept.imagePrompt
        try Data(prompt.utf8).write(to: directory.appendingPathComponent("prompt.txt"), options: .atomic)
        try Task.checkCancellation()
        let t2 = Date()
        let avatar: Data
        if fm.fileExists(atPath: avatarURL.path) { avatar = try Data(contentsOf: avatarURL) }
        else {
            let selfie = try Data(contentsOf: selfieURL)
            avatar = demo ? selfie : try await client.portrait(selfie: selfie, prompt: prompt, config: config)
            try avatar.write(to: avatarURL, options: .atomic)
        }
        metrics.imageSeconds = Date().timeIntervalSince(t2)
        try Task.checkCancellation()
        let t3 = Date()
        try CardRenderer.render(name: name, title: concept.title, number: number, artwork: avatar, directory: directory)
        metrics.renderingSeconds = Date().timeIntervalSince(t3); metrics.totalSeconds = Date().timeIntervalSince(clock)
        try encoder.encode(metrics).write(to: directory.appendingPathComponent("metrics.json"), options: .atomic)
        return metrics
    }
}
