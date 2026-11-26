import XCTest
@testable import AlterEgoCore

final class CoreTests: XCTestCase {
    func testGenerationBounded() {
        let jobs = (1...5).map { GuestJob(number: $0, name: "Guest", fact: "Fact") }
        XCTAssertEqual(QueuePolicy.nextGeneration(jobs.reversed(), active: 1).map(\.number), [1, 2])
        XCTAssertTrue(QueuePolicy.nextGeneration(jobs, active: 3).isEmpty)
    }
    func testPrintingUsesReadinessNotArrival() {
        var a = GuestJob(number: 1, name: "A", fact: "Fact")
        var b = GuestJob(number: 2, name: "B", fact: "Fact")
        a.generation = .ready; a.printing = .queued; a.printQueuedAt = Date(timeIntervalSince1970: 200)
        b.generation = .ready; b.printing = .queued; b.printQueuedAt = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(QueuePolicy.nextPrint([a,b])?.number, 2)
        b.printing = .submitted
        XCTAssertEqual(QueuePolicy.nextPrint([a,b])?.number, 1)
    }
    func testInterruptedPrintRequiresReview() {
        var job = GuestJob(number: 1, name: "A", fact: "B")
        job.generation = .ready; job.printing = .submitting
        job.recover(cardExists: true)
        XCTAssertEqual(job.printing, .needsReview)
        XCTAssertNil(QueuePolicy.nextPrint([job]))
    }
    func testInterruptedGenerationCheckpoint() {
        var job = GuestJob(number: 1, name: "A", fact: "B")
        job.generation = .generating; job.recover(cardExists: false)
        XCTAssertEqual(job.generation, .failed)
        job.generation = .generating; job.recover(cardExists: true)
        XCTAssertEqual(job.generation, .ready); XCTAssertEqual(job.printing, .queued)
    }
    func testStoreRecovery() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try JobStore(root: dir)
        var job = GuestJob(number: 1, name: "A", fact: "B")
        try store.create(job, selfie: Data([1,2,3]))
        job.generation = .generating; try store.save(job)
        XCTAssertEqual(try store.load().jobs.first?.generation, .failed)
        job.generation = .generating; try store.save(job)
        try Data([4]).write(to: store.file(job.id, "card.jpg"))
        let loaded = try store.load()
        XCTAssertEqual(loaded.jobs.first?.generation, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file(job.id, "selfie.jpg").path))
        XCTAssertTrue(loaded.warnings.isEmpty)
    }
    func testDefaultLunaUsesFastProcessing() throws {
        let config = PipelineConfig()
        let data = try OpenAIClient.conceptRequestBody(fact: "I collect watches", model: config.textModel)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["service_tier"] as? String, "fast")
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "none")
        let alternateData = try OpenAIClient.conceptRequestBody(fact: "Fact", model: "gpt-6.1-terra")
        let alternate = try XCTUnwrap(JSONSerialization.jsonObject(with: alternateData) as? [String: Any])
        XCTAssertNil(alternate["service_tier"])
        XCTAssertEqual(config.imageModel, "gpt-image-2.6-flare")
    }
    func testLunaFastRequest() throws {
        let model = PipelineConfig().textModel
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenAIClient.conceptRequestBody(fact: "I collect watches", model: model)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["service_tier"] as? String, "fast")
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "none")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(PipelineConfig().imageModel, "gpt-image-2.6-flare")
        let other = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenAIClient.conceptRequestBody(fact: "I collect watches", model: "gpt-6.1-terra")) as? [String: Any])
        XCTAssertNil(other["service_tier"])
    }
    func testResponseParsing() throws {
        let concept = "{\"title\":\"The Chronomancer\",\"imagePrompt\":\"A clockmaker\"}"
        let json = try JSONSerialization.data(withJSONObject: ["status":"completed","output":[["type":"reasoning"],["content":[["type":"output_text","text":concept]]]]])
        XCTAssertEqual(try OpenAIClient.parseConcept(json).title, "The Chronomancer")
        XCTAssertEqual(try OpenAIClient.parseImage(Data("{\"data\":[{\"b64_json\":\"YWJj\"}]}".utf8)), Data("abc".utf8))
        XCTAssertThrowsError(try OpenAIClient.parseImage(Data("{\"data\":[]}".utf8)))
    }
}
