# WinterVoice

WinterVoice is a native macOS dictation app with a primary window, menu-bar utility, and non-activating recording overlay. It supports a generic OpenAI-compatible remote transcription endpoint and retains owner-clean local-model lifecycle boundaries; local inference is blocked until an approved model artifact and whisper.cpp dependency are selected.

> **Status:** working provider/capture MVP with local History and Dictionary. Remote transcription is operational after configuration; Local mode is truthfully unavailable because no supported model is published. Global hotkeys, privacy prompts, microphone capture, remote endpoint interoperability, cross-app insertion, and the new History/Dictionary UX require manual verification in a signed local run.

The original future-platform architecture, domain, roadmap, and security specification is preserved in [docs/architecture-spec.md](docs/architecture-spec.md). This README describes the implemented MVP.

## MVP behavior

- Native primary window with a `NavigationSplitView` sidebar for Overview, Permissions, Transcription, Hotkey, and Privacy. The window opens at launch and can be reopened from the menu bar or with Command-0.
- First-launch page wizard for Microphone, Input Monitoring, and Accessibility. Each page shows live shared status and explicit request/settings actions; deferral never marks setup complete.
- Local vs Remote provider mode is persisted. Remote Providers configures a generic OpenAI-compatible base URL, model, optional language, and optional Keychain API key for endpoints that require Bearer authentication. Blank key input leaves an existing key unchanged; **Use Without Authentication** explicitly removes it. Models exposes installed/active lifecycle but no fake download while the approved catalog is empty.
- Successfully inserted dictations are stored locally in a bounded History list with search, deletion, and clear-all actions. History stores text and timestamps only; audio is never persisted.
- Dictionary stores enabled source/replacement pairs locally, rejects duplicate source phrases, applies longer matches first without replacement cascades, and runs before insertion and History recording.
- Native menu-bar menu with a monochrome microphone/waveform template symbol, live dictation and hotkey-health rows, the Right Option instruction, and actions to open WinterVoice, reopen the permission guide, open Settings, or quit. The app has no persistent Dock icon (`LSUIElement`).
- The macOS application icon is derived at standard 16–1024 pixel representations from the exact artwork stored at `WinterVoice/Resources/AppIconSource/WinterVoiceAppIcon.png`; run `scripts/generate-app-icons.sh` after intentionally replacing that source.
- Right Option push-to-talk via a listen-only Quartz event tap. The physical key is identified by key code 61, transitions are edge-deduplicated, and disabled event taps are re-enabled or surfaced as unavailable.
- A non-activating floating `NSPanel` displays preparing, recording, processing, inserting, and failure states.
- AVAudioEngine capture converts microphone input to mono 16 kHz PCM Float32 in memory. Capture starts only after the selected provider is ready.
- Text insertion into the originally focused Accessibility element. Direct selected-text insertion is attempted first. Clipboard/Command-V fallback runs only after reactivating the original app and verifying that the exact captured AX element is still focused.
- Clipboard fallback snapshots all pasteboard item types that expose data, restores them after paste, and avoids overwriting a clipboard changed by another app or the user in the meantime.
- Exactly three macOS permissions: Microphone captures audio; Input Monitoring observes global Right Option; Accessibility captures the focused field and inserts into the focused app. System Settings opens only through an explicit user action.

## Architecture

The app uses SwiftUI-appropriate VIPER and constructor composition:

```text
AppContainer
├── Onboarding: View, Presenter, Interactor (launch gate and completion persistence)
├── AppShell: View, Presenter (navigation and provider-status presentation)
├── View: MenuBarView, RecordingPanelView, Settings/Permissions views
├── Presenter: DictationPresenter (shared live dictation and permission state)
├── Interactor: DictationInteractor (dictation use-case and state coordination)
├── Router: AppRouter (app navigation and System Settings routes)
├── Entities: DictationState, permissions, insertion target
└── Platform adapters
    ├── RightOptionEventTap
    ├── SystemAudioRecorder + ConfiguredTranscriber
    ├── RemoteTranscriptionProvider + KeychainCredentialStore
    ├── ModelManager
    ├── SystemTextInjector
    └── SystemPermissionManager
```

Views render Presenter state and emit actions. The Presenter does not own capture or use-case sequencing. The Interactor coordinates the use case behind a small interface and does not touch Apple frameworks directly. Platform details remain in adapters, and `AppContainer` is the only constructor composition root. There are no MVVM-named types or third-party runtime dependencies.

## Requirements

- Apple Silicon Mac first
- macOS 14 or later
- Xcode 26.5 tested (a recent Xcode with Swift 6 support is expected)
- For remote use: an owner-configured OpenAI-compatible transcription endpoint

## Build and test

Open `WinterVoice.xcodeproj` in Xcode, select the WinterVoice scheme, configure your development team/signing, and run the app. For a non-signing command-line compile and test:

```sh
xcodebuild \
  -project WinterVoice.xcodeproj \
  -scheme WinterVoice \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/WinterVoiceDerived \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

The committed Xcode project is generated by `scripts/generate-project.rb` using the host's Ruby `xcodeproj` gem. This is a development-time project-generation convenience, not an app dependency. The generated project uses deterministic UUIDs and is committed, so normal users do not need the gem.

When sources or resources change, regenerate with `ruby scripts/generate-project.rb`. Run it twice and compare hashes for `project.pbxproj` and the shared scheme; both runs must be byte-identical.

## First run and manual verification

1. Build and run from Xcode with local signing after clearing the app's onboarding preference (or use **Permissions → Open Permission Guide**). Confirm the main window shows **Set up WinterVoice** before the normal sidebar and identifies the first permission that is not authorized.
2. Exercise denial and deferral: decline an available system prompt, confirm the guide reports the actual denied status and offers System Settings, then choose **Use With Limitations**. Confirm the main UI remains usable, explains unavailable functionality on Overview/Permissions, and **Permissions → Open Permission Guide** returns to setup without changing macOS permission grants.
3. Walk the Microphone, Input Monitoring, and Accessibility pages. A denied request must leave WinterVoice running and must not open System Settings automatically; use the explicit **Open System Settings** action. Return after each change; WinterVoice rechecks automatically when it becomes active, with **Refresh Status** available as an explicit fallback. Do not accept trust until the status reads Allowed. Input Monitoring and Accessibility are separate TCC services: verify each one independently.
4. Prepare a repeatable local-signed build before checking TCC. Run `ruby scripts/generate-project.rb` first. Then in Xcode add the owner’s normal Apple ID under **Xcode → Settings → Accounts** and select the owner’s **Personal Team** in the WinterVoice target’s **Signing & Capabilities**. Xcode may write `DEVELOPMENT_TEAM` and target metadata into the working `project.pbxproj` after that selection; this is the owner’s local signed-run configuration, not a team ID generated or committed by this repository. Keep **Automatic signing**, the stable bundle ID `com.winterzxzz.WinterVoice`, and no manually added provisioning profile, entitlement, or capability. If the generator is run again, it may clear that local team selection and metadata, so regenerate first and reselect the Personal Team before the next signed run. A paid Developer Program membership, distribution signing, and notarization are not required for this local workflow. If Xcode reports that this bundle ID is unavailable for the Personal Team, report that actual uniqueness conflict and stop—do not silently change the product identity.
5. Use one exact signed app copy for each TCC check. Build and run that copy from Xcode, confirm the process path, and close other WinterVoice instances yourself before enabling a service. Xcode may launch a DerivedData product, while another command-line build may live elsewhere; do not mix them. After pressing **Request**, WinterVoice invokes the supported native request for that service and shows the resulting shared status. It does not claim registration or authorization until the supported snapshot reads **Allowed**. System Settings opens only after the explicit **Open System Settings** action.
6. Verify **Input Monitoring** independently. With the exact signed copy running, choose **Request Input Monitoring**, then use **Open System Settings** and inspect Privacy & Security → Input Monitoring. Enable only the matching listed WinterVoice build. If no matching entry appears, do not enable an unrelated entry: the OS has not registered/listed this running build for that check, so close duplicate copies, relaunch this same build, and request again. Input Monitoring may not show another prompt after denial; the explicit Settings route remains available. Return to WinterVoice and wait for its bounded activation recheck; if macOS requires a relaunch, quit and relaunch the same build, then accept only the status shown by WinterVoice.
7. Verify **Accessibility** independently. With the exact signed copy running, choose **Request Accessibility**, then use **Open System Settings** and inspect Privacy & Security → Accessibility. Enable only the matching listed WinterVoice build. If no matching entry appears, do not enable an unrelated entry: close duplicate copies, relaunch this same build, and request again. Return to WinterVoice and wait for its bounded activation recheck; if macOS requires a relaunch, quit and relaunch the same build, then accept only the status shown by WinterVoice. Input Monitoring and Accessibility are separate TCC services; a result for one does not establish the other.

For an exact-build check before enabling either service, compare the app path you launched with the app shown by the process list, then inspect that same bundle:

```sh
pgrep -alf WinterVoice
codesign -dv --verbose=4 "/path/to/the/running/WinterVoice.app" 2>&1 \
  | egrep 'Identifier=|TeamIdentifier=|CDHash=|Signature='
plutil -p "/path/to/the/running/WinterVoice.app/Contents/Info.plist" \
  | rg CFBundleIdentifier
```

The identifier must be `com.winterzxzz.WinterVoice`. If the output says `TeamIdentifier=not set` and `Signature=adhoc`, the ad-hoc build’s code identity can be tied to its current CDHash; a rebuild or alternate path can therefore be a different TCC client even when the bundle identifier matches. A Personal Team-signed build gives repeat local runs a stable selected signing identity, but the exact running path still matters. Keep only the intended copy running while checking Input Monitoring, then repeat the independent procedure for Accessibility.

8. With fewer than three Allowed statuses, confirm **Start Using WinterVoice** is unavailable. Once all three are Allowed, complete setup and confirm relaunch skips the wizard.
9. From the completed app, choose **Permissions → Open Permission Guide**. Confirm setup reappears with live Allowed statuses, the saved completion marker is reset, and completing it again restores direct-to-main launches. Also close and reopen the main window from the menu bar and with Command-0.
10. Confirm Transcription switches persisted Local/Remote mode. Remote Providers must accept a generic endpoint with no vendor default and store its key in Keychain. Models must state that no supported downloadable model is published and expose no fake download. Add a Dictionary entry, verify it is applied before insertion, then confirm the processed text appears in History and survives relaunch.
11. Before Input Monitoring is enabled, confirm Overview, Hotkey, Permissions, and the menu bar do not claim the hotkey is listening even if the process can create a listen-only event tap. After enabling it and returning to the app, confirm the status changes to “Listening for Right Option” when macOS applies trust; the shared permission snapshot and hotkey reconciliation run automatically on activation. Otherwise follow macOS’s quit/relaunch requirement.
12. With no ready provider, press Right Option and confirm the panel reports **No transcription provider is configured** without requesting Microphone, recording, or capturing a target. With a compatible Remote configured, verify Preparing → Recording → Processing → Inserting into TextEdit.
13. Repeat dictation at least five times to exercise audio/event-tap cleanup. Also press Left Option and verify it never starts dictation. Leave both Option keys released when returning from System Settings so no modifier edge is ambiguous.
14. Put rich content and text on the clipboard, dictate into an app that requires paste fallback, then verify the prior clipboard content is restored. During another fallback, copy something new while processing and verify WinterVoice does not overwrite that newer clipboard.
15. Start dictation in one field, then move focus before insertion. If AX direct insertion cannot succeed, fallback must show a failure and paste nowhere because the original field is no longer focused.
16. Exercise HTTP/auth/invalid-response failures against a controlled compatible endpoint and confirm only sanitized recovery messages are shown.
17. Inspect the app icon at Retina scale in Finder, the main window title bar, and the App Switcher. Temporarily show the app in the Dock if needed to inspect that surface because `LSUIElement` intentionally suppresses its persistent Dock tile. Confirm the supplied artwork is unchanged in composition and remains crisp from 16 pt through 512 pt.
18. Open the menu in both Light and Dark Mode. Confirm the microphone/waveform menu-bar symbol remains a sharp monochrome template mark, the surface is a standard macOS menu rather than a custom popover, and status, hotkey health, and “Hold Right Option to dictate” appear as native informational rows grouped above the actions.
19. Exercise every menu action: **Open WinterVoice** activates/reopens the main window, **Open Permission Guide…** activates that same window and presents the existing live onboarding flow, **Settings…** opens Settings, and **Quit WinterVoice** terminates the app. While dictating, confirm the status row follows preparing, recording, processing, inserting, and failure states; confirm hotkey health changes after Input Monitoring reconciliation.

## Scope and roadmap

Remote transcription is generic and operational; no vendor is named or defaulted. Local model download/install/verification/registry mechanics exist, but Local inference and a real catalog remain blocked. LLM processing, Screen Recording, login items, configurable hotkeys, and live waveform visualization remain roadmap work.

## Privacy and limitations

Audio is captured only when the selected provider is ready. Remote multipart encoding is created in memory; optional API keys live in Keychain and keys are never logged. Successfully inserted transcript text is stored locally in History; audio is not persisted and transcript text is not logged. Unauthenticated compatible endpoints receive no Authorization header. HTTPS is required except for explicitly configured localhost/private-LAN HTTP endpoints.

The narrow owner decision still required for a real Local catalog is: exact first model artifact, authoritative download URL, SHA-256, and license/redistribution suitability, plus approval of the whisper.cpp source/revision. The illustrative `example.com` descriptor is not functional product data.

Accessibility behavior varies by target app. Direct insertion uses the captured focused AX element. Paste fallback is deliberately bounded: it reactivates the original application and proceeds only if that exact AX element is still focused. This protects against text being pasted into the wrong field, but means apps that replace their Accessibility element during focus restoration will fail safely and require another dictation.

Clipboard restoration preserves pasteboard representations available as raw data. macOS pasteboard promises or provider-backed values that cannot be materialized as data are not representable by this MVP; fallback still avoids clobbering any clipboard changed after WinterVoice writes its temporary text.

## License

No license has been selected yet.
