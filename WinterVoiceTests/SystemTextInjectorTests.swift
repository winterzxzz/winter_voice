import AppKit
import XCTest
@testable import WinterVoice

/// Exercises `SystemTextInjector.insert` end to end through its injection
/// seams (target locator, pasteboard session, post-paste keystroke, sleep),
/// always with nil-element targets so the paste path runs deterministically.
///
/// `insert` always runs `activateAndVerify`, whose nil-element branch consults
/// the REAL frontmost application and live AX focus state — neither is
/// reachable through the initializer's seams. The test host is WinterVoice.app
/// itself (an LSUIElement accessory), which cannot reliably become frontmost,
/// so a target built from `NSRunningApplication.current` would fail the
/// frontmost-pid check on most machines. Tests instead aim the captured target
/// at the session's actual frontmost application: activating it is a no-op,
/// the pid check compares the app against itself, and the one remaining AX
/// refusal (`.noValue` for the focused element) is mirrored up front so
/// sessions that cannot satisfy it skip instead of failing on environment.
@MainActor
final class SystemTextInjectorTests: XCTestCase {
    func testPasteRestoresPriorClipboardWhenUnchanged() async throws {
        let harness = try makeHarness()
        let target = try harness.injector.captureTarget()

        let outcome = try await harness.injector.insert("dictated text", into: target)

        XCTAssertEqual(outcome, InsertionOutcome(landedInSecureField: false))
        XCTAssertEqual(harness.pasteboard.writtenTranscriptions, ["dictated text"])
        XCTAssertEqual(harness.pasteboard.snapshotCallCount, 1)
        XCTAssertEqual(harness.pasteboard.restoredItemBatches.count, 1)
        let restored = try XCTUnwrap(harness.pasteboard.restoredItemBatches.first?.first)
        XCTAssertEqual(restored.values.first?.0, .string)
        XCTAssertEqual(restored.values.first?.1, Data("prior clipboard".utf8))
    }

    func testPasteDoesNotRestoreWhenClipboardChangedDuringWindow() async throws {
        let harness = try makeHarness()
        harness.pasteboard.simulatesExternalWriteDuringPasteWindow = true
        let target = try harness.injector.captureTarget()

        _ = try await harness.injector.insert("dictated text", into: target)

        XCTAssertEqual(harness.pasteboard.writtenTranscriptions, ["dictated text"])
        XCTAssertTrue(
            harness.pasteboard.restoredItemBatches.isEmpty,
            "Restoring would destroy whatever the user copied during the paste window"
        )
    }

    func testWriteFailureRestoresAndThrows() async throws {
        let harness = try makeHarness(writeSucceeds: false)
        let target = try harness.injector.captureTarget()

        do {
            _ = try await harness.injector.insert("dictated text", into: target)
            XCTFail("Expected insert to throw when the pasteboard write fails")
        } catch let failure as DictationFailure {
            XCTAssertEqual(failure.message, "Could not prepare text for insertion.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(harness.pasteboard.restoredItemBatches.count, 1)
    }

    func testKeystrokeFailureRestoresAndThrows() async throws {
        let keystrokeFailure = DictationFailure(
            message: "Could not synthesize Paste.",
            recovery: "Check Accessibility permission and try again."
        )
        let harness = try makeHarness(keystrokeError: keystrokeFailure)
        let target = try harness.injector.captureTarget()

        do {
            _ = try await harness.injector.insert("dictated text", into: target)
            XCTFail("Expected insert to rethrow the keystroke failure")
        } catch let failure as DictationFailure {
            XCTAssertEqual(failure, keystrokeFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(
            harness.pasteboard.restoredItemBatches.count, 1,
            "An untouched clipboard is restored even when the keystroke fails"
        )
    }

    func testInsertReportsSecureFieldOutcome() async throws {
        let harness = try makeHarness(isSecureField: true)
        let target = try harness.injector.captureTarget()

        let outcome = try await harness.injector.insert("hunter2", into: target)

        XCTAssertEqual(outcome, InsertionOutcome(landedInSecureField: true))
    }

    private struct Harness {
        let injector: SystemTextInjector
        let pasteboard: PasteboardSessionSpy
    }

    private func makeHarness(
        isSecureField: Bool = false,
        writeSucceeds: Bool = true,
        keystrokeError: DictationFailure? = nil
    ) throws -> Harness {
        let application = try frontmostApplicationSatisfyingActivateAndVerify()
        let pasteboard = PasteboardSessionSpy(writeSucceeds: writeSucceeds)
        let priorItem = NSPasteboardItem()
        priorItem.setString("prior clipboard", forType: .string)
        pasteboard.priorItems = [PasteboardItemSnapshot(item: priorItem)]
        let injector = SystemTextInjector(
            targetLocator: TargetLocatorStub(target: FocusedAccessibilityTarget(
                application: application,
                element: nil,
                isSecureField: isSecureField
            )),
            pasteboard: pasteboard,
            postPasteKeystroke: { if let keystrokeError { throw keystrokeError } },
            sleep: { _ in }
        )
        return Harness(injector: injector, pasteboard: pasteboard)
    }

    /// Picks the application that deterministically passes the production
    /// checks in `activateAndVerify`, skipping when this session cannot
    /// satisfy them (headless runner without a frontmost app, or an
    /// AX-trusted host whose frontmost app reports no focused element).
    private func frontmostApplicationSatisfyingActivateAndVerify() throws -> NSRunningApplication {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw XCTSkip("No frontmost application in this session, so activateAndVerify's pid check can never pass.")
        }
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(frontmost.processIdentifier),
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        if status == .noValue {
            throw XCTSkip("The frontmost application reports no AX focused element, so activateAndVerify would refuse to paste.")
        }
        return frontmost
    }
}

@MainActor
private final class TargetLocatorStub: FocusedAccessibilityTargetLocating {
    private let target: FocusedAccessibilityTarget?
    init(target: FocusedAccessibilityTarget?) { self.target = target }
    func focusedTarget() -> FocusedAccessibilityTarget? { target }
}

@MainActor
private final class PasteboardSessionSpy: PasteboardSession {
    var priorItems: [PasteboardItemSnapshot] = []
    var simulatesExternalWriteDuringPasteWindow = false
    private let writeSucceeds: Bool
    private var successfulWrites = 0
    private var changeCountReadsSinceLastWrite = 0
    private(set) var snapshotCallCount = 0
    private(set) var writtenTranscriptions: [String] = []
    private(set) var restoredItemBatches: [[PasteboardItemSnapshot]] = []

    init(writeSucceeds: Bool = true) {
        self.writeSucceeds = writeSucceeds
    }

    /// `SystemTextInjector.paste` reads `changeCount` once right after a
    /// successful write (capturing its own change) and once more when deciding
    /// whether to restore. Advancing the value on that second read simulates
    /// another process writing the pasteboard inside the paste window.
    var changeCount: Int {
        changeCountReadsSinceLastWrite += 1
        let externalWrites = simulatesExternalWriteDuringPasteWindow && changeCountReadsSinceLastWrite > 1 ? 1 : 0
        return successfulWrites + externalWrites
    }

    func snapshotItems() -> [PasteboardItemSnapshot] {
        snapshotCallCount += 1
        return priorItems
    }

    func writeTranscription(_ text: String) -> Bool {
        writtenTranscriptions.append(text)
        changeCountReadsSinceLastWrite = 0
        guard writeSucceeds else { return false }
        successfulWrites += 1
        return true
    }

    func restoreItems(_ items: [PasteboardItemSnapshot]) {
        restoredItemBatches.append(items)
    }
}
