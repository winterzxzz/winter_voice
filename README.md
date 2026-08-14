<div align="center">

<img src="WinterVoice/Resources/AppIconSource/WinterVoiceAppIcon.png" width="140" alt="WinterVoice — free open-source macOS dictation app with offline Whisper speech-to-text" />

# WinterVoice

**Free, open-source voice dictation for macOS — private, on-device speech‑to‑text powered by Whisper.**

Hold a key. Speak. Release. Your words appear in any app — 100% offline, no subscription, no account.

**English · Tiếng Việt · 90+ languages**

[**⬇️ Download for Mac (.dmg)**](https://github.com/winterzxzz/winter_voice/releases/latest)

[![Latest release](https://img.shields.io/github/v/release/winterzxzz/winter_voice?label=Download&color=blue)](https://github.com/winterzxzz/winter_voice/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/winterzxzz/winter_voice/total?color=brightgreen)](https://github.com/winterzxzz/winter_voice/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://github.com/winterzxzz/winter_voice/releases/latest)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-orange)](https://github.com/winterzxzz/winter_voice/releases/latest)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](WinterVoice)
[![GitHub stars](https://img.shields.io/github/stars/winterzxzz/winter_voice?style=social)](https://github.com/winterzxzz/winter_voice/stargazers)

**English** · [Tiếng Việt](README.vi.md)

<img src="docs/assets/widget-demo.gif" width="640" alt="WinterVoice floating widget demo — hold a key, speak into the live waveform, and the transcribed text is inserted into any macOS app" />

</div>

---

## What is WinterVoice?

WinterVoice is a **native macOS dictation app** that turns your voice into text in *any* application — Slack, Notes, your browser, your IDE. It runs [whisper.cpp](https://github.com/ggml-org/whisper.cpp) **entirely on your Mac**, so your voice never leaves your machine. Prefer your own server? Point it at any **OpenAI-compatible transcription API** instead.

It's the free, private alternative to paid dictation tools — built with SwiftUI, for Apple Silicon.

## ⬇️ Download

**[Grab the latest `.dmg` from Releases →](https://github.com/winterzxzz/winter_voice/releases/latest)**

1. Open `WinterVoice.dmg` and drag **WinterVoice** into **Applications**.
2. First launch: the app is not notarized yet, so macOS may warn you. Either **right‑click → Open → Open**, or run:

   ```sh
   xattr -cr /Applications/WinterVoice.app
   ```

3. Follow the built-in permission wizard (Microphone, Input Monitoring, Accessibility) — WinterVoice needs exactly these three, nothing more.
4. Download a Whisper model on the **Transcription** page (checksums verified automatically) and start dictating.

> Building from source instead? See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## ✨ Features

| | |
|---|---|
| 🌊 **Floating widget with live waveform** | A draggable, always-on-top pill follows your dictation: brand mark at rest, a 7-band voice-reactive waveform while you speak, then transcribe/insert progress. |
| 🔒 **100% private, offline speech-to-text** | On-device Whisper transcription. Audio is never persisted, never uploaded, never logged. |
| ⌨️ **Global push-to-talk hotkey** | Hold Fn/Globe (or any key/modifier chord you record) to dictate into whatever app is focused. |
| 🌍 **90+ languages, Vietnamese included** | Multilingual Whisper models with a dedicated language picker — great for Vietnamese speech-to-text on Mac. |
| 📝 **Types into any app** | Inserts text directly at your cursor via Accessibility, with a safe clipboard fallback that restores your clipboard afterwards. |
| ☁️ **Bring your own API (optional)** | Any OpenAI-compatible `/audio/transcriptions` endpoint — your server, your key (stored locally on your Mac). |
| 📚 **Personal dictionary** | Auto-replace phrases before insertion — fix names, jargon, and Whisper quirks once. |
| 🕘 **Local history** | Searchable dictation history stored only on your Mac. Secure fields are never recorded. |
| 🖥️ **Native & lightweight** | SwiftUI menu-bar app with a floating recording overlay. No Electron, no telemetry, no account. |

## 📸 Screenshots

The floating widget sits above your work and follows your dictation — idle, listening with a live waveform, transcribing, inserting:

<img src="docs/assets/widget-states.png" alt="WinterVoice floating widget states: idle brand pill, recording with live voice waveform, transcribing spinner, and inserting text" />

<details>
<summary><b>▶ App tour (main window)</b></summary>
<br/>
<img src="docs/assets/demo.gif" width="760" alt="WinterVoice app tour — home dashboard with usage stats, searchable dictation history, personal dictionary, and shortcut settings" />
</details>

| Searchable local history | Personal dictionary |
|---|---|
| ![Dictation history with search in WinterVoice, a free macOS speech-to-text app](docs/assets/history.png) | ![Personal auto-correct dictionary in WinterVoice for fixing misheard words](docs/assets/dictionary.png) |

| Usage stats at a glance | Configurable shortcuts |
|---|---|
| ![WinterVoice home dashboard with dictation stats: words, speaking time, words per minute](docs/assets/home.png) | ![Push-to-talk and toggle recording keyboard shortcuts in WinterVoice](docs/assets/shortcuts.png) |

## 🚀 How it works

1. **Hold** your push-to-talk key — a floating overlay shows it's listening.
2. **Speak** — audio is captured as 16 kHz mono PCM in memory only.
3. **Release** — Whisper transcribes on-device, your dictionary rules apply, and the text lands at your cursor.

## 🔐 Privacy, by design

- Local transcription runs on the pinned, checksum-verified **whisper.cpp v1.8.3** XCFramework; models are official artifacts verified by SHA-256.
- Audio lives in memory only — it is **never written to disk**.
- History stores text + timestamps locally; text dictated into password/secure fields is never recorded.
- Remote mode is opt-in, generic, HTTPS-first, and stores the API key **locally on your Mac** with owner-only file permissions.
- Exactly three permissions, each explained in-app: Microphone, Input Monitoring, Accessibility.

## 💻 Requirements

- **macOS 14 (Sonoma) or later**
- **Apple Silicon** (M1/M2/M3/M4) first-class
- ~80 MB–500 MB disk for a Whisper model (Tiny/Base/Small)

## ❓ FAQ

<details>
<summary><b>Is WinterVoice free?</b></summary>
Yes — free and open source. No subscription, no account, no trial limits.
</details>

<details>
<summary><b>Does it work offline?</b></summary>
Yes. Local mode runs whisper.cpp entirely on your Mac. Internet is only needed once, to download a model.
</details>

<details>
<summary><b>Does it support Vietnamese speech-to-text?</b></summary>
Yes — pick a multilingual Whisper model and set the language to Vietnamese (or leave auto-detect on). Tiếng Việt hoạt động tốt với model multilingual.
</details>

<details>
<summary><b>How is this different from macOS built-in dictation?</b></summary>
WinterVoice gives you push-to-talk from any app, open Whisper models you choose, a personal auto-correct dictionary, searchable history, and the option to use your own transcription server — all open source.
</details>

<details>
<summary><b>macOS says the app "cannot be opened". What do I do?</b></summary>
The build isn't notarized yet. Right-click the app → <b>Open</b> → <b>Open</b>, or run <code>xattr -cr /Applications/WinterVoice.app</code> once.
</details>

<details>
<summary><b>Which Whisper models are available?</b></summary>
Tiny, Base, and Small — each in multilingual (incl. Vietnamese) and English-only variants, downloaded from official whisper.cpp sources and verified against published SHA-256 checksums.
</details>

## 🗺️ Roadmap

- [ ] Signed & notarized releases
- [ ] LLM post-processing (punctuation, formatting, commands)
- [ ] Live waveform visualization
- [ ] Launch at login
- [ ] Homebrew cask

Full architecture & product spec: [docs/architecture-spec.md](docs/architecture-spec.md)

## 🤖 Vibe-coded with AI

WinterVoice is built end-to-end with **vibe coding** — [Claude Code](https://claude.com/claude-code) (Anthropic's Claude, Fable 5) writes the Swift, the tests, the release tooling, this README, and even the demo GIF pipeline, with [Winter](https://github.com/winterzxzz) steering the product. Tools in the loop:

- **[Claude Code](https://claude.com/claude-code)** — AI pair programmer driving the whole codebase
- **codegraph MCP** — a code-intelligence graph the AI queries instead of grepping
- **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** — the on-device speech engine underneath it all

If you're curious what a fully vibe-coded native macOS app looks like, read the commit history — every commit is co-authored with the AI.

## 🤝 Contributing

Stars, issues, and PRs are all welcome — if WinterVoice saves you typing, **give it a ⭐ so more people find it**.

Developer setup, project generation, build/test commands, and the manual verification checklist live in [**docs/DEVELOPMENT.md**](docs/DEVELOPMENT.md).

## ⭐ Star history

[![Star History Chart](https://api.star-history.com/svg?repos=winterzxzz/winter_voice&type=Date)](https://star-history.com/#winterzxzz/winter_voice&Date)

## 📄 License

No license has been selected yet.

---

<div align="center">
<sub><b>Keywords:</b> macOS dictation app · speech to text Mac · voice typing macOS · offline transcription · whisper.cpp GUI · Whisper macOS · Vietnamese speech recognition · push-to-talk dictation · private voice-to-text · free Mac dictation software</sub>
</div>
