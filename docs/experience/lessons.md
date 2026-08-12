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

## 2026-08-12 — Observable presenters must import their owning framework

**Workspace and episode:** `winter_voice`; adding the first-launch onboarding
presenter.

**What was expected and what happened:** The new presenter declared
`ObservableObject` and `@Published`, but its initial source skeleton omitted
`import Combine`. The first focused compile failed before behavioral tests could
run.

**Cost paid:** One compile failure and a narrow import correction.

**What would have avoided it:** When adding a standalone observable presenter,
import the framework that owns its property wrappers in the initial skeleton,
then compile as soon as the module boundary exists.

**Scope:** This project — its framework-light SwiftUI VIPER presenter files.

**Proposed amendment:** None.

## 2026-08-12 — Invoke the Ruby project generator through Ruby

**Workspace and episode:** `winter_voice`; regenerating the Xcode project for
the application icon asset catalog.

**What was expected and what happened:** The first attempt invoked
`scripts/generate-project.rb` directly, but the repository does not mark that
file executable. The generation step stopped before changing project output.

**Cost paid:** One interrupted generator invocation and retry.

**What would have avoided it:** Use the repository's documented command,
`ruby scripts/generate-project.rb`, rather than relying on executable mode.

**Scope:** This project — its Ruby/xcodeproj generation workflow.

**Proposed amendment:** None. The README now records the exact invocation.

## 2026-08-12 — Validate asset-catalog JSON as JSON

**Workspace and episode:** `winter_voice`; validating the new macOS AppIcon
catalog.

**What was expected and what happened:** `plutil -lint` was tried against the
asset catalog's `Contents.json`, but that tool expected plist syntax and
rejected otherwise valid JSON. Validation had to be repeated with `jq`, then
confirmed by the successful asset-catalog compiler build.

**Cost paid:** One inconclusive validation attempt and replacement check.

**What would have avoided it:** Validate `Contents.json` structure with a JSON
parser and use `actool`/the Xcode build plus compiled-product inspection for
the platform contract.

**Scope:** This project — its Xcode asset-catalog validation workflow.

**Proposed amendment:** None.

## 2026-08-12 — Provider and model lifecycles need one truth owner and transactional storage

**Workspace and episode:** `winter_voice`; replacing Apple Speech with configurable
Remote transcription and a downloadable Local-model lifecycle.

**What was expected and what happened:** The first integration duplicated provider
readiness between static shell copy and dynamic configuration, replaced Keychain
credentials destructively, fabricated download progress, and left descriptor,
cancellation, and rollback invariants incomplete. Later review also found that an
optional API key could not be explicitly removed, size-dependent model work still
ran on the main actor, and model deletion could leave files and registry state out
of sync when persistence failed.

**Cost paid:** Three bounded rejection/rework loops, a storage-ownership redesign,
and repeated focused plus full validation runs.

**What would have avoided it:** Derive provider readiness and user-facing status
from one owner; model optional credentials across enable, preserve-on-blank,
explicit disable, and disable failure; validate external descriptors before side
effects; report measured cancellable transfer progress; isolate large file work in
an actor; and make file-plus-registry mutations transactional with recoverable
backups and rollback.

**Scope:** This project — its provider configuration, Keychain adapter, and local
model storage lifecycle.

**Proposed amendment:** Preserve these invariants in the repository architecture
specification and provider/model regression coverage.

## 2026-08-12 — TCC verification must identify one signed app path before permission testing

**Workspace and episode:** `winter_voice`; onboarding Input Monitoring and
Accessibility registration/refresh diagnosis.

**What was expected and what happened:** The stable bundle identifier was expected
to identify the app for local permission testing, but two ad-hoc-signed WinterVoice
copies were running from different build directories. They shared the bundle ID yet
had different CDHashes and no Team ID, so macOS could treat them as distinct TCC
clients. Separately, a delayed permission snapshot could become Allowed after the
one startup hotkey reconciliation had already run.

**Cost paid:** Runtime evidence was ambiguous until both process paths and signing
requirements were inspected, and one additional integration regression/rework loop
was needed to bind delayed permission changes to hotkey reconciliation.

**What would have avoided it:** Before manual TCC verification, close duplicate app
copies, identify the exact running bundle path, and inspect its bundle/signing
identity. For repeat local testing, select the owner's Personal Team after project
generation and keep one build path. Subscribe runtime capability reconciliation to
the shared permission snapshot rather than assuming the first activation read is
final.

**Scope:** This project — its generated Xcode signing workflow, onboarding, and
Right Option event-tap lifecycle.

**Proposed amendment:** Keep the exact-path Personal Team procedure and delayed
permission-to-hotkey invariant in the README and regression suite.
