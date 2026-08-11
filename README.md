# WinterVoice

A native macOS voice dictation app. Hold a global hotkey, speak, release — the transcription is inserted into whatever app you are focused on.

Built as a **voice transcription platform**, not a Whisper wrapper: speech recognition is an extensible provider system with local (on-device) and remote (OpenAI-compatible HTTP) backends behind the same domain protocol.

> **Status: pre-implementation.** This README is the architecture specification. No code has been written yet. See [Roadmap](#roadmap) for the phased plan.

---

## Table of Contents

- [Goals](#goals)
- [User Flow](#user-flow)
- [Technology Stack](#technology-stack)
- [Architecture Overview](#architecture-overview)
- [Directory Structure](#directory-structure)
- [Domain Model](#domain-model)
- [Component Responsibilities](#component-responsibilities)
- [Dependency Direction & Ownership](#dependency-direction--ownership)
- [Concurrency Model](#concurrency-model)
- [AppKit + SwiftUI Interaction](#appkit--swiftui-interaction)
- [Model Management](#model-management)
- [Remote Providers](#remote-providers)
- [Text Processing & Insertion](#text-processing--insertion)
- [Permissions](#permissions)
- [Security](#security)
- [Logging](#logging)
- [Testing Strategy](#testing-strategy)
- [Technical Risks](#technical-risks)
- [Roadmap](#roadmap)
- [Building](#building)
- [License](#license)

---

## Goals

| Goal | Meaning |
| --- | --- |
| Native macOS integration | Swift + SwiftUI + AppKit only. No Electron, Tauri, React Native, Flutter, or web views. |
| Low latency | Push-to-talk release → inserted text with minimal perceptible delay. |
| Local / offline first | Transcription runs on-device by default. Nothing leaves the machine unless configured. |
| Optional remote endpoints | Any OpenAI-compatible transcription API — hosted, self-hosted, or LAN. |
| User-downloadable models | Models are downloaded on demand, never bundled in the `.app`. |
| Extensible runtimes | whisper.cpp first; CoreML / MLX / Parakeet / Moonshine can be added without touching the app layer. |
| System-wide insertion | Text lands in the focused app, whatever it is. |

**Targets:** Apple Silicon first · macOS 14+ · latest stable Xcode & Swift.

Third-party dependencies are avoided. Apple frameworks are preferred wherever they are viable.

---

## User Flow

```
1. User holds the global push-to-talk hotkey (default: Right Option)
2. Microphone capture starts
3. A floating panel appears indicating recording is active
4. User releases the hotkey
5. Capture stops
6. Audio is routed to the configured transcription provider (local or remote)
7. Text is processed (dictionary, normalization)
8. Text is inserted into the focused application
9. The transcription is optionally stored in local history
```

**Example.** The user is focused on Slack. They hold Right Option and say *"Can you send me the latest build?"*, then release. The sentence appears in the Slack composer.

---

## Technology Stack

| Concern | Framework |
| --- | --- |
| UI | SwiftUI, AppKit where SwiftUI is insufficient (`NSPanel`, `MenuBarExtra` hosting) |
| Concurrency | Swift Concurrency — `async/await`, actors, structured tasks |
| Audio | AVFoundation / `AVAudioEngine`, `AVAudioConverter` |
| Global hotkey | CoreGraphics / Quartz Event Services (`CGEventTap`) |
| Text insertion | macOS Accessibility APIs (`AXUIElement`), `NSPasteboard`, `CGEvent` |
| Networking | `URLSession` (multipart uploads, background downloads) |
| Persistence | SwiftData (history, dictionary, installed-model registry), Keychain (credentials) |
| Local inference | whisper.cpp via a C interop target |
| Logging | `OSLog` / `Logger` |

---

## Architecture Overview

The central rule: **the application must not be coupled to Whisper.** Everything above the runtime layer speaks in domain types.

```
                        ┌──────────────────┐
                        │  HotkeyManager   │  CGEventTap, push-to-talk
                        └────────┬─────────┘
                                 │ start / stop
                                 ▼
                        ┌──────────────────┐
                        │ DictationCoord.  │  explicit state machine
                        └────────┬─────────┘
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
     ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
     │ AudioRecorder  │ │RecordingPanel  │ │  TextInjector  │
     │ AVAudioEngine  │ │  Controller    │ │ AX → Clipboard │
     └───────┬────────┘ └────────────────┘ └────────▲───────┘
             │ RecordedAudio                        │ processed text
             ▼                                      │
     ┌────────────────────┐              ┌──────────┴─────────┐
     │TranscriptionService│─────────────▶│TextProcessorPipeline│
     └─────────┬──────────┘              └────────────────────┘
               │ selects via
               ▼
        ┌──────────────┐
        │ProviderPolicy│  primary + fallback
        └──────┬───────┘
        ┌──────┴───────────────────────┐
        ▼                              ▼
┌────────────────────┐      ┌─────────────────────┐
│LocalTranscription  │      │RemoteTranscription  │
│     Provider       │      │     Provider        │
└─────────┬──────────┘      └──────────┬──────────┘
          │                            │ multipart/form-data
          ▼                            ▼
┌────────────────────┐              URLSession
│ LocalModelRuntime  │  protocol
└─────────┬──────────┘
          ├── WhisperCPPRuntime  (WhisperContextActor → whisper.cpp C API)
          └── future: CoreMLRuntime, MLXRuntime, ParakeetRuntime, …
```

Orthogonal to the transcription path, and deliberately separate from it:

```
ModelManager
├── ModelCatalogService      remote → cached → bundled catalog
├── ModelDownloader          URLSession background downloads, progress, cancel, resume
├── ModelStorage             Application Support layout, FileManager only
├── ModelVerifier            SHA-256 validation
└── InstalledModelRegistry   what is on disk, which is active
```

> **Downloading a model and executing a model are separate concerns.** `ModelManager` knows nothing about inference; `LocalModelRuntime` knows nothing about HTTP.

---

## Directory Structure

```
WinterVoice
│
├── App
│   ├── WinterVoiceApp.swift        @main, MenuBarExtra, Settings scene
│   ├── AppContainer.swift          composition root, constructor DI
│   └── AppDelegate.swift           NSApplicationDelegate bridging
│
├── Core
│   ├── Audio                       AudioRecording, AVAudioEngineRecorder, format conversion
│   ├── Hotkeys                     HotkeyManager, CGEventTap, HotkeyBinding
│   ├── Permissions                 PermissionManager, PermissionStatus
│   ├── TextInjection               TextInjector, Accessibility + Clipboard impls
│   └── Logging                     Log categories, redaction helpers
│
├── Transcription
│   ├── Domain                      AudioInput, TranscriptionResult, TranscriptionConfiguration,
│   │                               TranscriptionProvider, DictationError
│   ├── TranscriptionService.swift  orchestration entry point
│   ├── Providers
│   │   ├── Local                   LocalTranscriptionProvider
│   │   └── Remote                  RemoteTranscriptionProvider, OpenAICompatibleClient,
│   │                               RemoteProviderConfiguration
│   └── Processing                  TextProcessor, pipeline, Dictionary/Punctuation/Replacement
│
├── Models
│   ├── Catalog                     ModelCatalogService, ModelDescriptor, catalog decoding
│   ├── Download                    ModelDownloader, DownloadProgress
│   ├── Storage                     ModelStorage, InstalledModel, InstalledModelRegistry
│   ├── Runtime                     LocalModelRuntime, RuntimeRegistry
│   └── WhisperCPP                  WhisperCPPRuntime, WhisperContextActor, CWhisper interop
│
├── Features
│   ├── MenuBar                     MenuBarView, MenuBarViewModel
│   ├── RecordingPanel              RecordingPanelController (NSPanel), RecordingPanelView
│   ├── Settings                    SettingsWindow + per-section views
│   ├── Models                      model browser / installed models UI
│   ├── History                     history list, search, export
│   └── Dictionary                  custom replacement editor
│
├── Persistence
│   ├── SwiftData                   HistoryRepository, DictionaryRepository, schema
│   └── Keychain                    KeychainStore, CredentialReference
│
└── Resources
    ├── catalog.json                bundled fallback model catalog
    └── Info.plist                  usage descriptions, LSUIElement
```

Structure is practical, not maximal — no artificial module explosion up front. Splitting into SwiftPM targets happens only when a boundary is proven.

---

## Domain Model

The protocols and types below are the contract every layer agrees on. **No whisper.cpp type ever escapes `Models/WhisperCPP`.**

### Transcription

```swift
protocol TranscriptionProvider {
    var id: String { get }

    func transcribe(
        audio: AudioInput,
        configuration: TranscriptionConfiguration
    ) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let detectedLanguage: String?
    let duration: TimeInterval
    let processingTime: TimeInterval
}
```

`TranscriptionResult` is designed to grow: word timestamps, per-segment confidence, segments, model metadata, and provider metadata are all additive.

### Audio

```swift
protocol AudioRecording {
    func start() async throws
    func stop() async throws -> RecordedAudio
}
```

Capture is mono, converted to **16 kHz PCM Float32** — the format whisper.cpp expects — in memory. Temporary files are written only when a provider genuinely requires a file (e.g. multipart upload encoding), never as the default path.

### Recording State Machine

Recording state is an explicit machine, never a scatter of booleans:

```swift
enum DictationState {
    case idle
    case preparing
    case recording
    case processing
    case inserting
    case failed(DictationError)
}
```

```
idle → preparing → recording → processing → inserting → idle
                                    │
                                    └──▶ failed(_) → idle
```

Invalid transitions are rejected by the coordinator, and the transition table is unit-tested independently of any Apple framework.

### Local Runtime

```swift
protocol LocalModelRuntime {
    var runtimeID: String { get }

    func supports(model: InstalledModel) -> Bool
    func load(model: InstalledModel) async throws
    func unload() async

    func transcribe(
        audio: AudioInput,
        configuration: TranscriptionConfiguration
    ) async throws -> TranscriptionResult
}
```

### Model Descriptor

Models are **data, not an enum**. New models ship by updating a JSON catalog, not by editing Swift:

```swift
struct ModelDescriptor: Identifiable, Codable {
    let id: String
    let displayName: String

    let family: String          // "whisper"
    let runtime: String         // "whisper.cpp"

    let variant: String         // "large-v3-turbo"
    let quantization: String?   // "q5_0"

    let downloadURL: URL
    let fileName: String

    let fileSize: Int64
    let sha256: String?

    let languages: [String]?
}
```

### Errors

```swift
enum DictationError: Error {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case audioRecordingFailed
    case modelNotInstalled
    case modelLoadFailed
    case modelInferenceFailed
    case remoteProviderUnavailable
    case authenticationFailed
    case invalidRemoteResponse
    case textInsertionFailed
}
```

Every case maps to a user-facing message with a concrete remedy. Errors are never surfaced as raw `NSError` descriptions.

---

## Component Responsibilities

| Component | Owns | Explicitly does not |
| --- | --- | --- |
| `AppContainer` | Object graph construction and lifetime | Business logic |
| `HotkeyManager` | `CGEventTap` lifecycle, key-down/up → push-to-talk events | Know what recording is |
| `DictationCoordinator` | The state machine, sequencing audio → transcription → processing → insertion | Touch AVAudioEngine or HTTP directly |
| `AudioRecorder` | `AVAudioEngine` graph, tap installation, format conversion, device-change handling | UI, persistence |
| `TranscriptionService` | Selecting a provider via `ProviderPolicy`, running it, applying fallback | Know about whisper.cpp or URLSession specifics |
| `ProviderPolicy` | Primary/fallback ordering and retry decisions | Perform transcription |
| `LocalTranscriptionProvider` | Resolving the active model → runtime, invoking it | C interop |
| `RemoteTranscriptionProvider` | Multipart request construction, response decoding, error mapping | Store credentials |
| `WhisperCPPRuntime` | Model load/unload, inference, all C pointer handling | Leak C types outward |
| `ModelManager` (+ sub-services) | Catalog, download, storage, verification, registry | Inference |
| `TextProcessorPipeline` | Ordered application of `TextProcessor`s | Insert text |
| `TextInjector` | Getting a string into the focused app, clipboard preservation | Transform text |
| `PermissionManager` | Querying and requesting microphone / accessibility status | Prompt in a loop |
| `RecordingPanelController` | `NSPanel` lifecycle, positioning, show/hide animation | Own dictation state |
| `HistoryRepository` | SwiftData reads/writes for transcriptions | Business rules |
| `KeychainStore` | Secret storage and retrieval by reference | Know about providers |

Deliberately avoided: giant thousand-line managers, global mutable singletons, and premature abstraction. A protocol exists only where it marks a real boundary (a seam that is swapped, faked in tests, or crosses a layer).

---

## Dependency Direction & Ownership

```
Features (SwiftUI views, view models)
        │  depends on
        ▼
Application services (DictationCoordinator, TranscriptionService, ModelManager)
        │  depends on
        ▼
Domain protocols & value types  ◀── nothing below depends upward
        ▲
        │  implemented by
Infrastructure (AVAudioEngine, CGEventTap, URLSession, whisper.cpp, SwiftData, Keychain)
```

- Dependencies point **inward toward the domain**. Infrastructure implements domain protocols; the domain never imports infrastructure.
- `AppContainer` is the only place that knows every concrete type. Everything else receives dependencies through its initializer.
- Views render state and emit actions. Views never perform HTTP, drive `AVAudioEngine`, read Keychain, call whisper.cpp, download files, or synthesize keyboard events.
- MVVM is used where it helps and not applied dogmatically; simple views bind to a service's observable state directly.

---

## Concurrency Model

| Work | Execution context |
| --- | --- |
| UI state | `@MainActor` — view models and panel controllers are main-actor isolated |
| `CGEventTap` callback | Runs on the tap's run loop; immediately hops to the coordinator's actor. The callback itself does the minimum possible work |
| Audio tap buffers | Real-time audio thread — no allocation, no locks, no `async`; buffers are handed off through a lock-free path to an actor |
| Model inference | Off the main actor, inside `WhisperContextActor`; a single actor serializes access to one `whisper_context` |
| Networking / downloads | `async` `URLSession` APIs, cancellable via structured concurrency |
| Model registry | Actor-isolated; concurrent reads of installed models are safe |

Principles: structured concurrency over detached tasks; `DispatchQueue.main.async` is not used as a workaround; shared mutable state is owned by an actor or eliminated. Strict concurrency checking is enabled from the start so `Sendable` problems surface at compile time rather than at runtime.

---

## AppKit + SwiftUI Interaction

SwiftUI describes views; AppKit provides the window behaviors SwiftUI cannot express.

| Surface | Implementation |
| --- | --- |
| Menu bar | `MenuBarExtra` with a SwiftUI menu content view |
| Settings | SwiftUI `Settings` scene, sectioned by `TabView` |
| Floating recorder | `NSPanel` (`.nonactivatingPanel`, `.floating` level, `hidesOnDeactivate = false`) hosting a SwiftUI view via `NSHostingView`, owned by `RecordingPanelController` |
| App lifecycle | `NSApplicationDelegateAdaptor` for event-tap setup, login item, termination cleanup |

The panel must float above normal windows, **never steal keyboard focus** (otherwise the target app loses focus and insertion breaks), appear within a frame or two of the hotkey press, and animate out after insertion. No SwiftUI view manages an `NSPanel`'s lifecycle.

Panel states:

```
idle        🎙
recording   ● ▂▄▆█▆▄▂       (live waveform from audio levels)
processing  Processing…
```

The app runs as an accessory (`LSUIElement`) — there is no permanently open main window.

---

## Model Management

### Storage layout

```
~/Library/Application Support/WinterVoice/
├── Models/
│   └── whisper/
│       ├── large-v3-turbo-q5/
│       │   ├── model.bin
│       │   └── metadata.json
│       └── small-q5/
│           ├── model.bin
│           └── metadata.json
├── Catalog/
│   └── catalog.json
└── Logs/
```

Paths are resolved through `FileManager.urls(for:in:)`. Home directory strings are never hard-coded.

### Catalog resolution

```
Remote catalog  →  Local cached catalog  →  Bundled fallback catalog
```

New models can therefore ship without an app release, and the app still works fully offline.

```json
{
  "id": "whisper-large-v3-turbo-q5",
  "name": "Whisper Large V3 Turbo Q5",
  "family": "whisper",
  "runtime": "whisper.cpp",
  "variant": "large-v3-turbo",
  "quantization": "q5_0",
  "download_url": "https://example.com/model.bin",
  "file_name": "ggml-large-v3-turbo-q5_0.bin",
  "size": 1700000000,
  "sha256": "..."
}
```

### Capabilities

Browse available models · download with live progress · cancel · resume where practical · verify SHA-256 · delete · select active · inspect metadata · **import a custom local model** (inspected, copied into Application Support, given metadata, matched to a runtime that claims it — imports are not assumed to be Whisper).

### Model lifecycle

The active model is **not** reloaded per transcription:

```
app start → active model known → load on first use → stay resident → reused across dictations
```

Switching models unloads the current context before loading the new one. The design leaves room for unloading under memory pressure later.

---

## Remote Providers

Any OpenAI-compatible transcription endpoint works: OpenAI, Groq, self-hosted Whisper servers, internal company endpoints, LAN inference boxes.

```
POST {baseURL}/audio/transcriptions
Content-Type: multipart/form-data

file=<audio>
model=<configured model>
language=<optional>
```

```swift
struct RemoteProviderConfiguration {
    let baseURL: URL
    let model: String
    let language: String?
    let credentialID: String?        // Keychain reference, never the key itself
    let additionalHeaders: [String: String]
}
```

**Test Connection** validates a configuration before it is relied on, and reports what actually went wrong:

```
✓ Connected successfully
✗ 401 Unauthorized — check the API key
✗ 404 Endpoint not found — check the base URL and path
✗ Invalid response format
✗ Connection timed out
```

Credentials never appear in diagnostics.

### Provider policy & fallback

```
Primary: Local        Primary: Remote
   │ success → done      │ success → done
   └ failure             └ failure
        ▼                     ▼
     Remote                 Local
```

Fallback is architectural from day one even though it does not get full UI in the MVP.

---

## Text Processing & Insertion

Dictation is **not** routed through an LLM. The default path is deterministic and fast:

```
Audio → Speech model → DictionaryProcessor → TextNormalizer → TextInjector
```

```swift
protocol TextProcessor {
    func process(_ input: String) async -> String
}
```

Pipeline stages: `DictionaryProcessor`, `PunctuationProcessor`, `ReplacementProcessor`, and later an optional `LLMProcessor` — opt-in only.

### Custom dictionary

```
swift ui   → SwiftUI
swift data → SwiftData
x code     → Xcode
git hub    → GitHub
view model → ViewModel
next js    → Next.js
```

```swift
struct DictionaryEntry {
    let id: UUID
    let source: String
    let replacement: String
    let isEnabled: Bool
}
```

Replacements are applied predictably (longest-match first, word-boundary aware) and efficiently.

### Insertion

```swift
protocol TextInjector {
    func insert(_ text: String) async throws
}
```

```
Accessibility API (set value on the focused editable AXUIElement)
        ↓ unavailable / not editable / fails
Clipboard + synthesized ⌘V
```

The clipboard path **preserves and restores the user's previous clipboard contents** (all representable types, restored after the paste settles). Destroying someone's clipboard is a bug, not a trade-off. `ClipboardTextInjector` ships first; `AccessibilityTextInjector` slots in ahead of it without any caller changing.

---

## Permissions

Centralized in `PermissionManager`, surfaced with status in Settings, requested with a stated reason and never in a blind loop.

| Permission | Why | When |
| --- | --- | --- |
| **Microphone** | Record voice for transcription | Phase 1 |
| **Accessibility** | Observe the global hotkey and insert text into other applications | Phase 1 (event tap) / Phase 3 (insertion) |
| **Screen Recording** | Possible future context features | Not required |

---

## Security

- API keys live in the **macOS Keychain**. Never in `UserDefaults`, never in SwiftData, never in logs.
- Configuration stores only a **credential reference**.
- HTTP logging is sanitized — `Authorization` headers and key material are redacted at the logging boundary, not by convention.
- Model download URLs are validated; HTTPS is the default. Plain-HTTP localhost/LAN endpoints are permitted only when the user explicitly configures them.
- Downloaded model files are **data**. They are verified against a checksum when one is published, and never executed.
- Transcription text is not logged by default.

---

## Logging

Structured `OSLog` categories: `Audio`, `Hotkey`, `Transcription`, `Model`, `Network`, `TextInjection`, `Permissions`, `UI`.

Never logged: API keys, `Authorization` headers, transcription content (unless the user explicitly turns on debug logging).

---

## Testing Strategy

Non-UI logic is tested through protocol fakes. Apple's frameworks are not under test — our wrappers and state logic are.

```
TranscriptionStateMachineTests    valid and invalid transitions
RemoteTranscriptionProviderTests  request shape, response decoding, error mapping
ProviderPolicyTests               fallback ordering, failure classification
ModelCatalogTests                 remote → cache → bundled resolution, decoding
ModelStorageTests                 path layout, install, delete, collision handling
ModelVerifierTests                checksum pass/fail
DictionaryProcessorTests          replacement correctness and ordering
```

---

## Technical Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| `CGEventTap` requires Accessibility permission and can be silently disabled by the system | Hotkey stops working with no visible cause | Observe `kCGEventTapDisabledByTimeout` / `…ByUserInput` and re-enable; expose live tap health in Settings |
| Right Option is a modifier-only key | Needs `flagsChanged` handling, not `keyDown`/`keyUp`; distinguishing left vs right requires raw key codes | Model the binding as a modifier-aware type from the start rather than assuming character keys |
| Synthesized ⌘V is inherently racy | Text lands in the wrong app or is dropped if focus moves | Capture the frontmost app before recording; verify focus at insertion; restore clipboard only after the paste is observed |
| Accessibility insertion is inconsistent across apps | Electron/Java/terminal apps often reject `AXValue` writes | Treat AX as an optimization with clipboard as the guaranteed fallback |
| whisper.cpp C++ interop and build integration | Build fragility, Metal/Accelerate configuration, binary size | Isolate in a single interop target with a narrow C surface; pin the upstream revision |
| Real-time audio thread constraints | Glitches, priority inversion, crashes | No allocation or locking in the tap callback; hand off through a lock-free path |
| Inference latency on large models | Feels sluggish, undermines the core value | Keep models resident; default to a turbo/quantized variant; surface duration metrics |
| Memory footprint of large models | Pressure on smaller machines | Registry tracks resident size; architecture supports unload under pressure |
| App Sandbox vs. event taps and Accessibility | Hard limits on distribution channel | Hardened Runtime, direct distribution first; sandbox viability assessed before any Mac App Store attempt |
| Model download integrity and hosting | Corrupt or substituted model files | SHA-256 verification, HTTPS, atomic install into place |

---

## Roadmap

Implementation is incremental. The project compiles and runs at the end of every phase.

### Phase 1 — Capture ✱ *no transcription yet*
- Menu bar application shell (`MenuBarExtra`, accessory app)
- `PermissionManager` — microphone
- `AVAudioEngine` recording service with 16 kHz mono Float32 conversion
- `HotkeyManager` push-to-talk (`CGEventTap`, Right Option)
- Recording state machine
- Floating `NSPanel` recording indicator
- Verify captured audio is correct

### Phase 2 — Local transcription
- Local model abstraction, `ModelStorage`, one bundled model descriptor
- `WhisperCPPRuntime` + `WhisperContextActor`
- End-to-end: push-to-talk → audio → Whisper → text

### Phase 3 — Insertion
- Accessibility permission handling
- `ClipboardTextInjector` (clipboard preservation + synthesized ⌘V)
- First complete workflow: hotkey → Whisper → pasted into the focused app

### Phase 4 — Model manager
- Remote catalog, downloads with progress, checksum validation
- Installed models, delete, switch active model

### Phase 5 — Remote provider
- Base URL / model / language configuration
- API key in Keychain
- OpenAI-compatible transcription, Test Connection

### Phase 6 — Polish
- History (SwiftData) with search, copy, delete, clear
- Custom dictionary
- Full Settings: General, Hotkeys, Transcription, Models, Remote Providers, Dictionary, Privacy, Advanced
- Launch at Login
- Provider fallback UI

---

## Building

> Not yet applicable — implementation starts at Phase 1.

Planned requirements: macOS 14+, Apple Silicon, latest stable Xcode. Models are downloaded at runtime and are never committed to this repository.

---

## Code Quality Expectations

Small focused types · clear naming · no giant managers · no premature abstraction · protocols only at meaningful boundaries · no force unwraps outside genuinely justified cases · thorough error handling · comments that explain unusual macOS behavior and architectural decisions rather than restating syntax. [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) apply throughout.

---

## License

TBD.
