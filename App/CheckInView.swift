import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

@MainActor struct CheckInView: View {
    @ObservedObject var manager: JobManager
    @StateObject private var speech = SpeechService()
    @State private var step = 0
    @State private var name = ""
    @State private var photo: UIImage?
    @State private var cameraOpen = false
    @State private var cameraError: String?
    @State private var settingsOpen = false
    @State private var receipt: GuestJob?
    @State private var submitError: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var nameFocused: Bool
    @FocusState private var factFocused: Bool
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanFact: String { speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            OrbitalBackdrop()
            VStack(spacing: 0) {
                masthead.padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if receipt == nil { KioskStepIndicator(step: step).padding(.bottom, 10) }
                        switch step {
                        case 0: nameStep
                        case 1: factStep
                        case 2: selfieStep
                        default: confirmationStep
                        }
                    }
                    .frame(maxWidth: 630, alignment: .leading)
                    .padding(.horizontal, 28).padding(.vertical, 35)
                    .frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                footer.padding(.horizontal, 28).padding(.bottom, 24).padding(.top, 10)
            }
        }
        .foregroundStyle(Theme.cream)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $settingsOpen) { SettingsSheet(manager: manager).presentationDetents([.large]) }
        .fullScreenCover(isPresented: $cameraOpen) {
            CameraView { image in
                cameraOpen = false
                if let image { photo = image; cameraError = nil }
            }.ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image; cameraError = nil }
                else { cameraError = "Could not load the photo." }
            }
        }
        .onChange(of: name) { value in if value.count > 40 { name = String(value.prefix(40)) } }
        .onChange(of: speech.transcript) { value in if value.count > 600 { speech.transcript = String(value.prefix(600)) } }
    }
    private var masthead: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.brass.opacity(0.7), lineWidth: 1).frame(width: 42, height: 42)
                    Image(systemName: "sparkle").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.brass)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOUTHWIND LABS").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                    Text("HOLIDAY EXPEDITION / 2026").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Button { speech.stop(); settingsOpen = true } label: {
                Image(systemName: "gearshape").font(.system(size: 23, weight: .regular))
                    .frame(width: 48, height: 48).foregroundStyle(Theme.muted)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("Settings and print jobs")
        }
    }
    private func heading(_ kicker: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(kicker).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(Theme.brass)
            Text(title).font(.system(size: 62, weight: .regular, design: .serif)).tracking(-2).lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 21, weight: .regular)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("A ONE-NIGHT CHARACTER COLLECTION", "Meet your\nalter ego.", "A selfie, one fact, and a little creative magic. Leave with a character card made just for you.")
            VStack(alignment: .leading, spacing: 10) {
                Text("FIRST NAME").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Theme.brass)
                TextField("Your first name", text: $name)
                    .font(.system(size: 32, weight: .medium)).textContentType(.givenName).textInputAutocapitalization(.words).submitLabel(.next).focused($nameFocused)
                    .padding(20).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .onSubmit { if !cleanName.isEmpty && manager.canSubmit { nameFocused = false; step = 1 } }
            }
            Button { nameFocused = false; step = 1 } label: { HStack { Spacer(); Text("Begin"); Spacer(); Image(systemName: "arrow.right") } }
                .buttonStyle(PrimaryButtonStyle()).disabled(cleanName.isEmpty || !manager.canSubmit)
            if !manager.canSubmit { Text(manager.storageProblem ?? (manager.keyConfigured ? "Generation limit reached. See settings." : "Ask the host to configure the event API key in settings.")).font(.subheadline).foregroundStyle(Theme.brass) }
            Text("Your selfie and spoken fact are used to create artwork via an AI service. The original photo is removed from the app after successful generation; audio recognition stays on-device.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var factStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("THE RAW MATERIAL", "Tell us one thing.", "A hobby, an obsession, an unusual talent. The more specific, the better.")
            HStack(alignment: .center, spacing: 20) {
                Button {
                    factFocused = false
                    if speech.isRecording { speech.stop() } else { Task { await speech.start() } }
                } label: {
                    ZStack {
                        Circle().fill(speech.isRecording ? Theme.crimson : Theme.cream).frame(width: 86, height: 86)
                        if speech.isPreparing || speech.isFinishing { ProgressView().tint(Theme.midnight) }
                        else { Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 30, weight: .medium)).foregroundStyle(speech.isRecording ? Color.white : Theme.midnight) }
                    }
                }.buttonStyle(.plain).disabled(speech.isPreparing || speech.isFinishing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(speech.isRecording ? "Listening · \(speech.seconds)s / 15s" : speech.isFinishing ? "Finishing transcription…" : speech.isPreparing ? "Preparing microphone…" : "Tap to speak")
                        .font(.system(size: 22, weight: .semibold))
                    Text(speech.isRecording ? "Tap again when you're finished." : "Up to 15 seconds. No need to rehearse.").font(.system(size: 16)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }.padding(20).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 9) {
                Text("YOUR FACT · EDIT IF NEEDED").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(Theme.brass)
                TextField("I collect mechanical watches…", text: $speech.transcript, axis: .vertical)
                    .font(.system(size: 21)).lineLimit(2...4).focused($factFocused).disabled(speech.isRecording || speech.isFinishing || speech.isPreparing)
                    .padding(16).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                if let error = speech.error { Text(error).font(.subheadline).foregroundStyle(Theme.brass) }
            }
            Button { factFocused = false; step = 2 } label: { HStack { Spacer(); Text("Next: selfie"); Spacer(); Image(systemName: "arrow.right") } }
                .buttonStyle(PrimaryButtonStyle()).disabled(cleanFact.isEmpty || speech.isRecording || speech.isPreparing || speech.isFinishing)
            backButton { speech.reset(); step = 0 }
        }
    }
    private var selfieStep: some View {
        VStack(alignment: .leading, spacing: 19) {
            heading("THE FACE BEHIND THE LEGEND", "Strike a pose.", "Your character will be inspired by you. The rest is a surprise.")
            Button { openCamera() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.055))
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().frame(height: 270).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack { Spacer(); HStack { Spacer(); Label("Retake", systemImage: "camera.rotate").font(.system(size: 15, weight: .semibold)).padding(11).background(Theme.deep.opacity(0.9), in: Capsule()) } }.padding(14)
                    } else {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle().stroke(Theme.brass.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4,6])).frame(width: 100,height: 100)
                                Image(systemName: "camera").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.brass)
                            }
                            Text("Take a selfie").font(.system(size: 22, weight: .semibold))
                        }
                    }
                }.frame(height: 270).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
            }.buttonStyle(.plain)
            if !UIImagePickerController.isSourceTypeAvailable(.camera) { PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose a test photo", systemImage: "photo") }.foregroundStyle(Theme.brass) }
            if let cameraError { Text(cameraError).font(.subheadline).foregroundStyle(Theme.brass) }
            if let submitError { Text(submitError).font(.subheadline).foregroundStyle(Theme.brass) }
            Button { submit() } label: { HStack { Spacer(); Text("Create my alter ego"); Spacer(); Image(systemName: "sparkles") } }
                .buttonStyle(PrimaryButtonStyle()).disabled(photo == nil || !manager.canSubmit)
            backButton { step = 1 }
        }
    }
    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            Image(systemName: "checkmark.seal").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(Theme.brass).padding(.bottom, 8)
            heading("CREW NO. \(String(format: "%03d", receipt?.number ?? 0)) · ACCEPTED", "You're in,\n\(receipt?.name ?? "crew member").", "Grab a drink. Your character card will be waiting at the collection station when it's ready.")
            Button { reset() } label: { HStack { Spacer(); Text("Next guest"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(PrimaryButtonStyle())
            Text("Returning to the welcome screen automatically.").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }
    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("Back", systemImage: "arrow.left").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted).frame(minHeight: 44) }.buttonStyle(.plain)
    }
    private var footer: some View {
        HStack {
            Circle().fill(manager.printerConfigured && !manager.printPaused ? Theme.brass : Theme.muted).frame(width: 7, height: 7)
            Text(manager.printPaused ? "PRINTING PAUSED" : manager.printerConfigured ? "COLLECTION STATION" : "PRINTER NOT SELECTED").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
            Spacer()
            Text("\(manager.outstandingCount) IN PROCESS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
        }.foregroundStyle(Theme.muted)
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { cameraError = "Camera unavailable. Choose a test photo below."; return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { cameraError = nil; cameraOpen = true }
            else { cameraError = "Camera permission is disabled. Enable it in iPad Settings." }
        }
    }
    private func submit() {
        guard let photo, let data = CameraView.jpeg(photo) else { submitError = "Please take another photo."; return }
        do {
            let job = try manager.add(name: cleanName, fact: cleanFact, selfie: data)
            receipt = job; self.photo = nil; speech.reset(); name = ""; submitError = nil; step = 3
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if receipt?.id == job.id { reset() }
            }
        } catch { submitError = error.localizedDescription }
    }
    private func reset() { speech.reset(); name = ""; photo = nil; receipt = nil; selectedPhoto = nil; submitError = nil; cameraError = nil; step = 0 }
}
