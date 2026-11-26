import Foundation
import SwiftUI
import UIKit

@MainActor final class JobManager: ObservableObject {
    @Published private(set) var jobs: [GuestJob] = []
    @Published private(set) var keyConfigured = false
    @Published private(set) var printerURL: URL?
    @Published private(set) var printerName = "No printer selected"
    @Published private(set) var printPaused = false
    @Published private(set) var isPrinting = false
    @Published private(set) var isChoosingPrinter = false
    @Published var message: String?
    @Published private(set) var storageProblem: String?
    private var store: JobStore?
    private var key: String?
    private var active = Set<UUID>()
    private var foreground = true
    private let printService = PrintService()
    private let generationLimit = 3
    private let attemptLimit = 90
    private let defaults = UserDefaults.standard
    var generationAttempts: Int { jobs.reduce(0) { $0 + $1.generationAttempts } }
    var outstandingCount: Int { jobs.filter { $0.generation != .cancelled && $0.printing != .printed && $0.printing != .submitted && $0.printing != .cancelled }.count }
    var pendingPrintCount: Int { jobs.filter { $0.generation == .ready && [.queued,.failed,.needsReview].contains($0.printing) }.count }
    var canSubmit: Bool { keyConfigured && storageProblem == nil && generationAttempts + jobs.filter { $0.generation == .queued }.count < attemptLimit }
    var printerConfigured: Bool { printerURL != nil }

    init() {
        do {
            var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("AlterEgoJobs", isDirectory: true)
            let store = try JobStore(root: root)
            var values = URLResourceValues(); values.isExcludedFromBackup = true; try? root.setResourceValues(values)
            self.store = store
            let recovery = try store.load(); jobs = recovery.jobs
            if !recovery.warnings.isEmpty { storageProblem = recovery.warnings.joined(separator: "\n") }
        } catch { storageProblem = error.localizedDescription }
        key = Keychain.read(); keyConfigured = !(key ?? "").isEmpty
        printerURL = defaults.string(forKey: "printerURL").flatMap { URL(string: $0) }
        printerName = defaults.string(forKey: "printerName") ?? "No printer selected"
        printPaused = defaults.bool(forKey: "printPaused") || jobs.contains { $0.printing == .needsReview }
        if printPaused { defaults.set(true, forKey: "printPaused") }
    }
    func setForeground(_ active: Bool) { foreground = active; if active { pump() } }
    func configureKey(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try Keychain.save(value); key = Keychain.read(); keyConfigured = !(key ?? "").isEmpty; pump() }
        catch { message = error.localizedDescription }
    }
    func removeKey() {
        guard active.isEmpty else { message = "Wait for active generations to finish before removing the key."; return }
        do { try Keychain.remove(); key = nil; keyConfigured = false }
        catch { message = error.localizedDescription }
    }
    func choosePrinter() {
        guard !isPrinting && !isChoosingPrinter else { return }
        isChoosingPrinter = true
        printService.choose(current: printerURL) { [weak self] result in
            guard let self else { return }; self.isChoosingPrinter = false
            switch result {
            case .success(let printer):
                if let printer {
                    self.printerURL = printer.url; self.printerName = printer.displayName
                    self.defaults.set(printer.url.absoluteString, forKey: "printerURL"); self.defaults.set(printer.displayName, forKey: "printerName")
                }
            case .failure(let error): self.message = error.localizedDescription
            }
            self.pump()
        }
    }
    func setPrintPaused(_ value: Bool) { printPaused = value; defaults.set(value, forKey: "printPaused"); if !value { pump() } }
    func testPrint() {
        guard !isPrinting, !isChoosingPrinter, let printerURL else { return }
        do {
            let card = try printService.calibrationCard(); isPrinting = true
            printService.submit(card: card, printerURL: printerURL, name: "Alter Ego calibration") { [weak self] result in
                guard let self else { return }; self.isPrinting = false
                switch result {
                case .success: self.message = "Test job accepted. Verify the physical print, margins and colour."
                case .failure(let error): self.setPrintPaused(true); self.message = error.localizedDescription
                }
                self.pump()
            }
        } catch { message = error.localizedDescription }
    }
    func add(name: String, fact: String, selfie: Data) throws -> GuestJob {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, let store else { throw AlterEgoError.invalid(storageProblem ?? "Configure the event key or check the generation limit in Settings.") }
        guard !n.isEmpty, n.count <= 40, !f.isEmpty, f.count <= 600, !selfie.isEmpty else { throw AlterEgoError.invalid("Please enter a name, a fact, and take a selfie.") }
        let job = GuestJob(number: (jobs.map(\.number).max() ?? 0) + 1, name: n, fact: f)
        try store.create(job, selfie: selfie); jobs.append(job); pump(); return job
    }
    @discardableResult private func update(_ job: GuestJob) -> Bool {
        guard let store, let index = jobs.firstIndex(where: { $0.id == job.id }), storageProblem == nil else { return false }
        do { try store.save(job); jobs[index] = job; return true }
        catch { storageProblem = "Could not save job #\(job.number): \(error.localizedDescription). Stop and relaunch after checking storage."; return false }
    }
    func pump() {
        guard foreground, storageProblem == nil, let store else { return }
        if let key, !key.isEmpty {
            for var job in QueuePolicy.nextGeneration(jobs, active: active.count, limit: generationLimit) {
                guard generationAttempts < attemptLimit else { break }
                job.generation = .generating; job.generationError = nil; job.generationAttempts += 1
                guard update(job) else { break }
                active.insert(job.id)
                let pipeline = CharacterPipeline(client: OpenAIClient(apiKey: key))
                let id = job.id, name = job.name, fact = job.fact, number = job.number, directory = store.directory(job.id)
                Task { [weak self] in
                    do { _ = try await pipeline.run(name: name, fact: fact, number: number, directory: directory); self?.generationFinished(id, error: nil) }
                    catch { self?.generationFinished(id, error: error.localizedDescription) }
                }
            }
        }
        guard !printPaused, !isPrinting, !isChoosingPrinter, let printerURL, var job = QueuePolicy.nextPrint(jobs) else { return }
        job.printing = .submitting; job.printAttempts += 1; job.printError = nil
        guard update(job) else { return }
        isPrinting = true; let id = job.id
        printService.submit(card: store.file(id, "card.jpg"), printerURL: printerURL, name: "Alter Ego #\(job.number)") { [weak self] result in
            self?.printFinished(id, result: result)
        }
    }
    private func generationFinished(_ id: UUID, error: String?) {
        active.remove(id)
        guard var job = jobs.first(where: { $0.id == id }), job.generation == .generating else { pump(); return }
        if let error {
            job.generation = .failed; job.generationError = error
            _ = update(job)
        } else {
            job.generation = .ready; job.readyAt = Date(); job.printQueuedAt = job.readyAt; job.printing = .queued
            if update(job), let store { try? FileManager.default.removeItem(at: store.file(id, "selfie.jpg")) }
        }
        pump()
    }
    private func printFinished(_ id: UUID, result: Result<Void, Error>) {
        isPrinting = false
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        switch result {
        case .success: job.printing = .submitted
        case .failure(let error):
            job.printing = .needsReview; job.printError = error.localizedDescription
            setPrintPaused(true)
        }
        _ = update(job)
        // Yield to UIKit before opening another print interaction.
        Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds: 500_000_000); self?.pump() }
    }
    func retryGeneration(_ id: UUID) {
        guard generationAttempts < attemptLimit, var job = jobs.first(where: { $0.id == id }), job.generation == .failed else { return }
        job.generation = .queued; job.generationError = nil; if update(job) { pump() }
    }
    func cancelGeneration(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), [.queued,.failed].contains(job.generation) else { return }
        job.generation = .cancelled; job.printing = .cancelled
        if update(job), let store { try? FileManager.default.removeItem(at: store.file(id, "selfie.jpg")) }
    }
    func reprint(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), job.generation == .ready, job.printing != .submitting else { return }
        job.printing = .queued; job.printQueuedAt = Date(); job.printError = nil; if update(job) { pump() }
    }
    func markPrinted(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), job.generation == .ready, job.printing != .submitting else { return }
        job.printing = .printed; job.printError = nil; _ = update(job)
    }
    func cancelPrint(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), job.generation == .ready, job.printing == .queued else { return }
        job.printing = .cancelled; _ = update(job)
    }
    func exportPending() throws -> [URL] {
        guard printPaused, !isPrinting, let store else { throw AlterEgoError.invalid("Pause printing and wait for the current print request before exporting.") }
        let pending = jobs.filter { $0.generation == .ready && [.queued,.failed,.needsReview,.submitted].contains($0.printing) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlterEgo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Include unconfirmed submissions so the operator can reconcile physical prints first.
        return try pending.map { job in
            let url = dir.appendingPathComponent(String(format: "card-%03d-%@.jpg", job.number, job.printing.rawValue))
            try FileManager.default.copyItem(at: store.file(job.id, "card.jpg"), to: url); return url
        }
    }
    func cardURL(_ id: UUID) -> URL? { store?.file(id, "card.jpg") }
}
