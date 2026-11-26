import Foundation
import AlterEgoCore

@main struct Harness {
    static func main() async {
        do { try await run() } catch { FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, ["generate", "render"].contains(command) else {
            print("""
            alter-ego generate --name Alex --fact 'I collect watches' --selfie photo.jpg --out output/alex
              [--text-model gpt-6-luna] [--image-model gpt-image-2.6-flare] [--quality medium]
              [--prompt-file style.txt] [--number 1] [--demo] [--resume]
            alter-ego render --name Alex --out output/alex [--number 1] [--title 'The Chronomancer']
            GPT-6 Luna concept requests use Fast processing (service_tier=fast), reasoning effort none.
            Luna requests use Fast processing. Set OPENAI_API_KEY for live generation. --demo uses the input photo instead of AI.
            """); return
        }
        var options: [String: String] = [:]; var flags = Set<String>(); var i = 1
        while i < args.count {
            let arg = args[i]; guard arg.hasPrefix("--") else { throw AlterEgoError.invalid("Unexpected argument \(arg)") }
            if ["--demo", "--resume"].contains(arg) { flags.insert(arg); i += 1 }
            else { guard i+1 < args.count, !args[i+1].hasPrefix("--") else { throw AlterEgoError.invalid("Missing value for \(arg)") }; options[arg] = args[i+1]; i += 2 }
        }
        func required(_ k: String) throws -> String { guard let v = options[k], !v.isEmpty else { throw AlterEgoError.invalid("Missing \(k)") }; return v }
        let name = try required("--name"), out = URL(fileURLWithPath: try required("--out"), isDirectory: true)
        let number = Int(options["--number"] ?? "1") ?? 1
        if command == "render" {
            let concept = try JSONDecoder().decode(CharacterConcept.self, from: Data(contentsOf: out.appendingPathComponent("concept.json")))
            try CardRenderer.render(name: name, title: options["--title"] ?? concept.title, number: number, artwork: Data(contentsOf: out.appendingPathComponent("avatar.jpg")), directory: out)
            print("Rendered \(out.path)/card.jpg and card.pdf"); return
        }
        let fact = try required("--fact"), selfie = try Data(contentsOf: URL(fileURLWithPath: required("--selfie")))
        let demo = flags.contains("--demo")
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        guard demo || !apiKey.isEmpty else { throw AlterEgoError.invalid("Set OPENAI_API_KEY or pass --demo.") }
        let fm = FileManager.default
        if fm.fileExists(atPath: out.path), !flags.contains("--resume"), !(try fm.contentsOfDirectory(atPath: out.path)).isEmpty { throw AlterEgoError.invalid("Output directory is not empty. Use a new directory or --resume to reuse existing concept/avatar artifacts.") }
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        if !flags.contains("--resume") || !fm.fileExists(atPath: out.appendingPathComponent("selfie.jpg").path) { try selfie.write(to: out.appendingPathComponent("selfie.jpg"), options: .atomic) }
        var config = PipelineConfig()
        if let model = options["--text-model"] { config.textModel = model }
        if let model = options["--image-model"] { config.imageModel = model }
        if let quality = options["--quality"] { config.quality = quality }
        if let path = options["--prompt-file"] { config.houseStyle = try String(contentsOfFile: path, encoding: .utf8) }
        let pipeline = CharacterPipeline(client: OpenAIClient(apiKey: apiKey), config: config)
        let metrics = try await pipeline.run(name: name, fact: fact, number: number, directory: out, demo: demo)
        print(String(format: "Concept %.2fs | image %.2fs | render %.2fs | total %.2fs", metrics.conceptSeconds, metrics.imageSeconds, metrics.renderingSeconds, metrics.totalSeconds))
        print("Artifacts: \(out.path)")
    }
}
