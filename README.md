# Alter Ego

Native iPad check-in kiosk for Southwind Labs' 2026 holiday party. Three guest inputs (first name, spoken fact, selfie), one collectible full-colour character card, automatically queued for the Canon SELPHY CP1500. Designed for ~60 guests. No server, database engine, accounts, external Swift packages, or studio UI.

**Status:** first implementation, not a device-tested release. The portable shared Swift package was built and tested under Swift 6.2.1 on Linux. The iPad sources were syntax-parsed and the Xcode project/plist validated. Xcode, Apple frameworks, signing, live API calls, Core Graphics output, native camera/speech, and physical AirPrint were not executable in the build environment. Treat the hardware checklist below as release gates. Astra was not available as a callable reviewer; the design decisions in this project were made directly.

## 1. Start with the debug harness (Mac)

Requires macOS 13+ and Xcode's Swift 5.9+ toolchain. From the extracted project directory:

```sh
cd Core
swift test
swift run alter-ego generate \
  --name Alex \
  --fact 'I am obsessed with mechanical watches' \
  --selfie ../Fixtures/test-artwork.jpg \
  --out ../output/demo \
  --demo
open ../output/demo/card.jpg
```

`--demo` uses the fixture as artwork and a fixed concept. It makes no API calls and is only a renderer/layout test, not an AI quality test. The supplied illustration is an intentionally simple offline fixture, not a generated portrait.

For live generation, provide a real, consented JPEG selfie (upright, around 1000–1400 pixels) and the event project's API key via `OPENAI_API_KEY`. Avoid putting secrets in command-line arguments or checked-in files. In NuShell, `$env.OPENAI_API_KEY = '<your event key>'` sets the environment variable for the current session; unset it afterward. Shell history may retain the literal if pasted directly, so preferably populate it from your secure secret store.

```sh
swift run alter-ego generate \
  --name Alex \
  --fact 'I am obsessed with mechanical watches' \
  --selfie /path/to/selfie.jpg \
  --out ../output/alex \
  --image-model gpt-image-2.6-flare \
  --quality medium
```

The harness outputs `concept.json`, `prompt.txt`, `avatar.jpg`, `card.jpg`, `card.pdf`, and `metrics.json` with model selections and elapsed time per stage. It also stores the input selfie in the selected output folder for debugging; delete personal fixtures and outputs after use. `--resume` reuses saved concept/artwork checkpoints, **so use a fresh output directory when comparing models/prompts**. `--text-model`, `--image-model`, `--quality`, `--prompt-file`, and `--number` are optional. Model defaults live in `Models.swift`. The app and harness compile the same core source files.

To change a title or test template revisions without making another API request:

```sh
swift run alter-ego render --name Alex --out ../output/alex --title 'The Chronomancer'
```

The default image model is `gpt-image-2.6-flare` at medium quality and medium complexity. The structured text concept uses GPT-6 Luna with `model: "gpt-6-luna"`, `service_tier: "fast"`, and `reasoning.effort: "none"`. Fast processing is a request setting, not a separate model ID, and costs twice the standard Luna token rates. Alternate text model overrides do not automatically request Fast processing. These model IDs and the Responses/Images Edits endpoint formats were checked against the OpenAI API docs, but entitlement and rate limits depend on your project. Check the API account's usage dashboard for actual charges; latency metrics are not billed cost measurements. To compare Sunburst, pass `--image-model gpt-image-2.6-sunburst` in a fresh output directory.

## 2. Install the native app

Open `AlterEgo.xcodeproj` in Xcode 16 or newer. Select the AlterEgo target, then Signing & Capabilities, and choose your team. Change the bundle identifier if it is unavailable. Connect your iPad, enable Developer Mode if prompted, select it as the run destination, and build/run. Minimum iPadOS: 17. No App Store deployment or TestFlight is required for a local install. Verify provisioning lasts through the party.

On the iPad:

1. Connect the iPad and SELPHY to the venue LAN (printer needs compatible 2.4 GHz Wi-Fi; no client isolation). Internet is needed for OpenAI.
2. Tap the gear in the app and enter a dedicated event-only OpenAI key. The app stores it in a device-only Keychain item, not in its source or job files. Restrict the key to the required endpoints, configure spend alerts, and revoke it after the event. A locally installed client key is still a security trade-off; never distribute this app with your general API key.
3. Choose the AirPrint printer and run the calibration print. Verify the paper size, crop, colour and physical output. If no printer is selected, generated cards stay queued.
4. Check in with a real name, spoken fact, and selfie. Grant permissions when prompted. The app requires on-device speech recognition; if the device/language doesn't support it, it offers editable typed input rather than uploading audio.
5. Enable Guided Access if desired. Leave the iPad on external power with the app foregrounded. The app disables auto-lock while open. It does not claim to run AI work or print indefinitely while suspended by iPadOS.

## 3. Design

An editorial, retro-futurist holiday expedition rather than a cartoon Christmas-party template. Midnight blue, warm ivory, brass, and restrained crimson accents. Large serif headings with small technical monospaced labels, high-contrast fields, one primary action per screen, no style selection, no prompt editing, and no forced wait for AI. The concept prompt is specific to each fact; the style prompt keeps the 60 cards coherent. No generated text is used in the card typography. The name is dominant and the title is a conversation starter.

Physical card: 100 x 148 mm, portrait; 1200 x 1776 px (approximately 305 dpi), sRGB JPEG. A matching single-page PDF with exact physical dimensions is also saved for fallback printing. Artwork occupies most of the card, while the first name and title remain in a deterministic footer inside safe margins. The supplied asset is a temporary star emblem and text wordmark, not Southwind Labs' actual logo. Replace it with the real brand asset if desired.

## 4. Architecture

```
SwiftUI kiosk → local job directory → JobManager (@MainActor)
                                      ├─ up to 3 AI jobs (async)
                                      │   ├─ Responses: structured concept
                                      │   ├─ Images Edits: selfie + prompt
                                      │   └─ Core Graphics: JPEG and PDF
                                      └─ serial AirPrint submission
```

No generic workflow engine: one main-actor manager is the source of truth for state; the core performs async inference, deterministic rendering and atomic filesystem writes. A generation result is printed in completion order, not arrival order. The printer's own queue manages physical spooling. The app does **not** assume API completion proves the card physically emerged. Guest UI resets after a five-second receipt or immediately via Next guest. Guests collect cards separately.

Each guest gets a UUID directory under the app's Application Support/AlterEgoJobs: atomic `job.json`, input `selfie.jpg` while needed, `concept.json`, `prompt.txt`, `avatar.jpg`, `card.jpg`, `card.pdf`, `metrics.json`. The original selfie is removed once generation successfully commits; cancelled queued/failed jobs also remove their selfie. Failed jobs retain input/checkpoints for manual retry. Audio is processed by Apple's on-device recognizer and not stored as a file. Generated portraits, spoken fact text and cards remain local until the app/job data is removed. The job directory is excluded from device backup on a best-effort basis. Clear job data after the event by deleting the app (not offloading) after exporting cards you intend to keep; explicitly remove the Keychain key first. Cloud-provider retention is governed by provider terms, not local deletion.

### Recovery rules

- Generation interrupted before rendering: fail the job and allow manual retry, reusing persisted concept/artwork. No automatic duplicate paid requests.
- Generation interrupted after card creation: recover as ready and queue printing.
- Print interrupted or error: pause automatic printing and mark `needsReview`. Physically inspect the printer before requeueing. Successful UIKit completion is labeled `submitted`; operator can mark `printed`.
- Failed generation: retry from settings. No unlimited auto-retries. The app has a persistent 90-generation-attempt ceiling; this is a request-count guardrail, not a dollar cap. A corrupted job manifest or persistent storage failure stops new jobs to prevent accidental duplicate side effects.
- Multiple guests can continue checking in if printing is paused or unavailable. Internet/API failures create failed generation records to retry after recovery. Reprint never calls the AI APIs.

### Wired backup

The CP1500 does not officially support direct USB printing from an iPad. Bring a USB-C data cable and MacBook as a contingency. Pause automatic printing, wait until the current submission finishes, tap Export unconfirmed cards, and AirDrop or save the JPEGs to a shared location. Files include crew number and print state. **Check which submitted cards already physically printed** before sending files to the Mac. Install the printer on the Mac over USB, select the 100 x 148 mm/postcard media, and print the required cards. If using CUPS, inspect `lpstat -p` and `lpoptions -p PRINTER -l` to choose supported media settings. Mark physically printed cards in the app before resuming AirPrint. Do not blindly print the entire export batch.

## 5. Acceptance checklist

Before the party:

- [ ] Build iPad target and launch on actual iPad (not just simulator).
- [ ] Check microphone permissions and on-device recognition in a noisy room; typed fallback works.
- [ ] Verify front-camera framing and retake, plus accurate recognizable portraits for 5–10 diverse consenting test selfies.
- [ ] Compare Flare medium/high quality and Sunburst on the same fixture using separate output directories. Measure latency, likeness, creativity, and consistency. Select final config.
- [ ] Print calibration image and one real card. Verify crop, orientation, readability, lanyard fit and colour.
- [ ] Submit at least 8 guest jobs rapidly; verify no extra UI dialogs block intake and only one AirPrint submission is active.
- [ ] Unplug printer or run out of paper while a job is pending; confirm queue pauses or OS reports its state, manually reconcile and resume.
- [ ] Disable internet, check in a guest, reconnect and retry. Verify no duplicate artwork calls on print retry.
- [ ] Force-quit during generation and during print; reopen. Confirm checkpoint recovery and interrupted-print review.
- [ ] Test USB export/reconciliation with actual printer and Mac.
- [ ] Confirm venue SSID credentials, no client isolation, 2.4 GHz compatibility, internet uplink, and printer discovery.
- [ ] Bring RP-108 supplies, lanyards, iPad charger/stand, printer power/cable, and Mac fallback. Revoke event key and clear raw/retained guest data after the party.

## References

- OpenAI model catalog: https://developers.openai.com/api/docs/models
- GPT Image 2.6 Flare: https://developers.openai.com/api/docs/models/gpt-image-2.6-flare
- Image edits: https://developers.openai.com/api/docs/guides/image-generation
- Structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- Apple's on-device speech: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
- Native printing: https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller
