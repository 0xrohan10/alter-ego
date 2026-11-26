import SwiftUI
import UIKit

@MainActor struct SettingsSheet: View {
    @ObservedObject var manager: JobManager
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var share: ExportBatch?
    @State private var preview: CardPreview?
    @State private var confirmRemove = false
    var body: some View {
        NavigationStack {
            List {
                if let problem = manager.storageProblem { Section("Storage error") { Text(problem).foregroundStyle(.orange) } }
                if let message = manager.message { Section { HStack(alignment: .top) { Text(message).font(.subheadline); Spacer(); Button("Clear") { manager.message = nil }.buttonStyle(.borderless) } } }
                Section("Event API key") {
                    LabeledContent("Status", value: manager.keyConfigured ? "Stored in Keychain" : "Not configured")
                    SecureField("Enter dedicated event key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") { manager.configureKey(key); key = "" }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if manager.keyConfigured { Button("Remove key", role: .destructive) { confirmRemove = true } }
                    Text("\(manager.generationAttempts) / 90 generation attempts. Revoke the project key after the event.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Printer") {
                    LabeledContent("Selected", value: manager.printerName)
                    Button("Choose AirPrint printer") { manager.choosePrinter() }.disabled(manager.isPrinting || manager.isChoosingPrinter)
                    Button("Test print · calibration card") { manager.testPrint() }.disabled(!manager.printerConfigured || manager.isPrinting || manager.isChoosingPrinter)
                    Toggle("Pause automatic printing", isOn: Binding(get: { manager.printPaused }, set: { manager.setPrintPaused($0) }))
                    Button("Export unconfirmed cards") {
                        do { let urls = try manager.exportPending(); if urls.isEmpty { manager.message = "No cards to export." } else { share = ExportBatch(urls: urls) } }
                        catch { manager.message = error.localizedDescription }
                    }.disabled(!manager.printPaused || manager.isPrinting)
                    Text("For USB fallback: pause, export JPEGs to the Mac, check which cards actually printed, then mark the rest as printed after printing. AirPrint submission is not physical-delivery verification.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Jobs · \(manager.jobs.count)") {
                    if manager.jobs.isEmpty { Text("Guest submissions will appear here.").foregroundStyle(.secondary) }
                    ForEach(manager.jobs.reversed()) { job in jobRow(job) }
                }
            }
            .navigationTitle("Settings & jobs")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { key = ""; dismiss() } } }
            .confirmationDialog("Remove the stored API key?", isPresented: $confirmRemove, titleVisibility: .visible) { Button("Remove key", role: .destructive) { manager.removeKey() } }
            .sheet(item: $share) { batch in ActivityView(items: batch.urls) }
            .sheet(item: $preview) { card in
                NavigationStack {
                    if let image = UIImage(contentsOfFile: card.url.path) { Image(uiImage: image).resizable().scaledToFit().padding(20).navigationTitle("Crew card") }
                    else { Text("Card unavailable.") }
                }
            }
        }.tint(Theme.brass)
    }
    private func jobRow(_ job: GuestJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%03d", job.number)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.name).font(.headline)
                Text(status(job)).font(.subheadline).foregroundStyle(job.generation == .failed || job.printing == .needsReview ? Color.orange : .secondary)
                if let error = job.generationError ?? job.printError { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            }
            Spacer()
            Menu {
                if job.generation == .failed { Button("Retry generation", systemImage: "arrow.clockwise") { manager.retryGeneration(job.id) } }
                if [.queued,.failed].contains(job.generation) { Button(role: .destructive) { manager.cancelGeneration(job.id) } label: { Label("Cancel generation", systemImage: "xmark") } }
                if job.generation == .ready {
                    Button("Preview card", systemImage: "photo") { if let url = manager.cardURL(job.id) { preview = CardPreview(url: url) } }
                    if job.printing != .submitting {
                        if job.printing != .queued { Button("Queue reprint", systemImage: "printer") { manager.reprint(job.id) } }
                        if job.printing != .printed { Button("Mark physically printed", systemImage: "checkmark") { manager.markPrinted(job.id) } }
                        if job.printing == .queued { Button(role: .destructive) { manager.cancelPrint(job.id) } label: { Label("Cancel print", systemImage: "xmark") } }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 38) }
            .disabled(job.generation == .generating || job.generation == .cancelled)
        }.padding(.vertical, 4)
    }
    private func status(_ job: GuestJob) -> String {
        switch job.generation {
        case .queued: return "Waiting for AI"
        case .generating: return "Generating artwork"
        case .failed: return "Generation failed"
        case .cancelled: return "Cancelled"
        case .ready:
            switch job.printing {
            case .waiting, .queued: return "Ready · queued to print"
            case .submitting: return "Sending to AirPrint"
            case .submitted: return "Submitted · not physically verified"
            case .needsReview, .failed: return "Check printer before retrying"
            case .printed: return "Printed · confirmed"
            case .cancelled: return "Print cancelled"
            }
        }
    }
    private struct ExportBatch: Identifiable { let id = UUID(); let urls: [URL] }
    private struct CardPreview: Identifiable { let id = UUID(); let url: URL }
}
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
