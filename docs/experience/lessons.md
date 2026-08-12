# WinterVoice experience lessons

Append-only project-specific lessons from implementation and validation.

## 2026-08-12 — Generated Xcode projects need path and determinism checks

**Workspace and episode:** `winter_voice`; initial native macOS project generation.

**What was expected and what happened:** The generated project was expected to
build immediately and regenerate without churn. Its first checked-in form
resolved `INFOPLIST_FILE` at the repository root even though the file lived
under `WinterVoice/Resources`, so the build failed before Swift compilation.
Fresh project generation also required deterministic UUID handling before the
project and shared scheme remained byte-identical across runs.

**Cost paid:** Two build/rework cycles and an explicit generator-idempotence
pass.

**What would have avoided it:** Run the exact clean command-line build as soon
as project generation lands, then regenerate twice and compare project and
scheme hashes. Treat the generator as the source of truth rather than patching
only `project.pbxproj`.

**Scope:** This project — its Ruby/xcodeproj generator and committed project.

**Proposed amendment:** Keep the clean build/test command and deterministic
generation contract in the repository README.

## 2026-08-12 — Apple framework adapters need explicit lifecycle invariants

**Workspace and episode:** `winter_voice`; speech capture and clipboard
insertion adapters.

**What was expected and what happened:** Initial cleanup removed an
`AVAudioEngine` input tap even when no tap had been installed, and clipboard
restoration covered only successful paste completion. Those paths could have
triggered an AVAudioEngine precondition failure or destroyed the user's prior
clipboard after a later insertion error.

**Cost paid:** Rejection-level source review and adapter rework before runtime
acceptance.

**What would have avoided it:** State resource invariants before implementation:
track whether the audio tap is installed and centralize idempotent teardown;
after replacing the pasteboard, restore every materializable prior item on
every exit while refusing to overwrite a newer external clipboard change.

**Scope:** This project — its AVFoundation and AppKit adapters.

**Proposed amendment:** Retain these invariants in the architecture and manual
verification guidance.

## 2026-08-12 — Every insertion strategy shares the exact-focus precondition

**Workspace and episode:** `winter_voice`; insertion into the app focused when
dictation began.

**What was expected and what happened:** Exact focused-element verification
initially guarded only the clipboard fallback. Direct Accessibility insertion
could still write to a formerly focused element after the user moved focus
during recognition.

**Cost paid:** A final rejection and refactor after the first green build.

**What would have avoided it:** Define target identity once at the insertion
boundary: reactivate the captured application and require its currently focused
AX element to equal the captured element before any direct or fallback write.

**Scope:** This project — its focused-app insertion security invariant.

**Proposed amendment:** Preserve the invariant in the repository architecture
specification and signed manual smoke test.

## 2026-08-12 — Swift 6 treats an Accessibility option symbol as shared mutable state

**Workspace and episode:** `winter_voice`; complete strict-concurrency build of
the permission adapter.

**What was expected and what happened:** Using
`kAXTrustedCheckOptionPrompt` directly looked like the canonical Accessibility
API call, but Swift 6 imports it as mutable global state and rejected the
reference under complete concurrency checking.

**Cost paid:** One compile/rework loop after the project-path failure was fixed.

**What would have avoided it:** Keep strict checking enabled and isolate the C
framework quirk at the adapter edge by using the API's documented option-key
string, rather than weakening concurrency checking globally.

**Scope:** This project — its Swift 6 Accessibility adapter implementation.

**Proposed amendment:** None.

## 2026-08-12 — Regenerate the Xcode project before testing new source files

**Workspace and episode:** `winter_voice`; hotkey reliability regression tests.

**What was expected and what happened:** The first focused Xcode test command
appeared green but executed only the six existing tests. Newly added Swift test
files are included by this repository's project generator, not discovered
dynamically by the already-generated project, so the intended hotkey tests were
absent until regeneration. After regeneration, the new suite produced the real
pre-implementation compile-red and later passed against the production seam.

**Cost paid:** One misleading green invocation, one regeneration, and a repeated
focused test run.

**What would have avoided it:** Run `scripts/generate-project.rb` immediately
after adding Swift source or test files, then verify the intended test class and
case names appear in `xcodebuild` output.

**Scope:** This project — its committed generated Xcode project workflow.

**Proposed amendment:** Keep project regeneration explicit in contribution and
validation instructions.

## 2026-08-12 — Cross-file SwiftUI destination metadata needs internal visibility

**Workspace and episode:** `winter_voice`; splitting the multi-surface AppShell
across navigation and operational-view files.

**What was expected and what happened:** Destination titles, icons, and planned
descriptions were initially placed in a private extension beside the shell
view. The adjacent planned-feature view also consumed that metadata, so the
first compile failed on access control.

**Cost paid:** One compile failure and a narrow visibility correction.

**What would have avoided it:** When one entity's presentation metadata is
shared by multiple files in the same feature, keep it at the default internal
scope or give it a dedicated feature-local presentation type. Reserve private
extensions for consumers contained in the same file.

**Scope:** This project — its SwiftUI AppShell file boundaries.

**Proposed amendment:** None.
