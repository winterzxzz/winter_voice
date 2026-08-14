import AppKit

struct FocusedAccessibilityTarget {
    let application: NSRunningApplication
    let element: AXUIElement?
    let isSecureField: Bool

    init(application: NSRunningApplication, element: AXUIElement?, isSecureField: Bool = false) {
        self.application = application
        self.element = element
        self.isSecureField = isSecureField
    }
}

@MainActor
protocol FocusedAccessibilityTargetLocating: AnyObject {
    func focusedTarget() -> FocusedAccessibilityTarget?
}

@MainActor
final class SystemFocusedAccessibilityTargetLocator: FocusedAccessibilityTargetLocating {
    private let frontmostTarget: () -> FocusedAccessibilityTarget?
    private let systemWideTarget: () -> FocusedAccessibilityTarget?
    private let frontmostApplication: () -> NSRunningApplication?

    init(
        frontmostTarget: (() -> FocusedAccessibilityTarget?)? = nil,
        systemWideTarget: (() -> FocusedAccessibilityTarget?)? = nil,
        frontmostApplication: (() -> NSRunningApplication?)? = nil
    ) {
        self.frontmostTarget = frontmostTarget ?? Self.frontmostFocusedTarget
        self.systemWideTarget = systemWideTarget ?? Self.systemWideFocusedTarget
        self.frontmostApplication = frontmostApplication ?? { NSWorkspace.shared.frontmostApplication }
        // AX lookups are IPC into the focused app; the default ~6 s messaging
        // timeout can stall the main thread behind an unresponsive app.
        // Passing the system-wide element bounds every AX call this process makes.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

    func focusedTarget() -> FocusedAccessibilityTarget? {
        systemWideTarget()
            ?? frontmostTarget()
            ?? frontmostApplication().map { FocusedAccessibilityTarget(application: $0, element: nil) }
    }

    private static func frontmostFocusedTarget() -> FocusedAccessibilityTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = Self.attribute(kAXFocusedUIElementAttribute, of: applicationElement) else { return nil }
        return FocusedAccessibilityTarget(
            application: app,
            element: element,
            isSecureField: isSecureTextElement(element)
        )
    }

    private static func systemWideFocusedTarget() -> FocusedAccessibilityTarget? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let element = attribute(kAXFocusedUIElementAttribute, of: systemWide) else { return nil }
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success,
              let application = NSRunningApplication(processIdentifier: processIdentifier) else { return nil }
        return FocusedAccessibilityTarget(
            application: application,
            element: element,
            isSecureField: isSecureTextElement(element)
        )
    }

    static func attribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success,
              let subrole = value as? String else { return false }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }
}

struct PasteboardItemSnapshot {
    let values: [(NSPasteboard.PasteboardType, Data)]

    init(item: NSPasteboardItem) {
        values = item.types.compactMap { type in
            item.data(forType: type).map { (type, $0) }
        }
    }

    func makeItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
    }
}

@MainActor
protocol PasteboardSession: AnyObject {
    var changeCount: Int { get }
    func snapshotItems() -> [PasteboardItemSnapshot]
    func writeTranscription(_ text: String) -> Bool
    func restoreItems(_ items: [PasteboardItemSnapshot])
}

@MainActor
final class SystemPasteboardSession: PasteboardSession {
    private let pasteboard: NSPasteboard = .general
    // De-facto standard markings honored by clipboard managers (Maccy, Paste,
    // Raycast, …): without them the dictated text survives in their history
    // even after WinterVoice restores the pasteboard.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    var changeCount: Int { pasteboard.changeCount }

    func snapshotItems() -> [PasteboardItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).map(PasteboardItemSnapshot.init)
    }

    func writeTranscription(_ text: String) -> Bool {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedType, Self.transientType], owner: nil)
        let wroteText = pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)
        pasteboard.setString("", forType: Self.transientType)
        return wroteText
    }

    func restoreItems(_ items: [PasteboardItemSnapshot]) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items.map { $0.makeItem() }) }
    }
}

/// Outcome of asking an application which element currently has focus.
enum FocusedElementQuery {
    /// The app answered with a focused element.
    case element(AXUIElement)
    /// The app answered and stated nothing has focus.
    case none
    /// The app could not answer (no AX support, tree not built, timeout).
    case unanswered
}

@MainActor
final class SystemTextInjector: TextInjecting {
    private struct CapturedTarget {
        let application: NSRunningApplication
        let element: AXUIElement?
        let isSecureField: Bool
    }

    private var targets: [UUID: CapturedTarget] = [:]
    private let targetLocator: FocusedAccessibilityTargetLocating
    private let pasteboard: PasteboardSession
    private let postPasteKeystroke: () throws -> Void
    private let sleep: (Duration) async throws -> Void
    private let directTextWriter: (AXUIElement, String) -> Bool
    private let focusedElementQuery: (pid_t) -> FocusedElementQuery

    init(
        targetLocator: FocusedAccessibilityTargetLocating = SystemFocusedAccessibilityTargetLocator(),
        pasteboard: PasteboardSession = SystemPasteboardSession(),
        postPasteKeystroke: (() throws -> Void)? = nil,
        sleep: ((Duration) async throws -> Void)? = nil,
        directTextWriter: ((AXUIElement, String) -> Bool)? = nil,
        focusedElementQuery: ((pid_t) -> FocusedElementQuery)? = nil
    ) {
        self.targetLocator = targetLocator
        self.pasteboard = pasteboard
        self.postPasteKeystroke = postPasteKeystroke ?? Self.postCommandV
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
        self.directTextWriter = directTextWriter ?? Self.verifiedDirectWrite
        self.focusedElementQuery = focusedElementQuery ?? Self.systemFocusedElementQuery
    }

    func captureTarget() throws -> TextInsertionTarget {
        guard let focused = targetLocator.focusedTarget() else {
            throw DictationFailure(message: "No editable field is focused.", recovery: "Focus a text field and try again.")
        }
        if focused.element == nil {
            // Chromium-based apps (Electron: Claude, Slack, VS Code, …) build
            // their accessibility tree lazily and report no focused element
            // until it exists. Electron documents this attribute as the switch
            // that forces the tree on; by insert time the real field is
            // queryable. Harmless elsewhere — unknown attributes are ignored.
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(focused.application.processIdentifier),
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
            )
        }
        let id = UUID()
        targets[id] = CapturedTarget(
            application: focused.application,
            element: focused.element,
            isSecureField: focused.isSecureField
        )
        return TextInsertionTarget(id: id)
    }

    @discardableResult
    func insert(_ text: String, into target: TextInsertionTarget) async throws -> InsertionOutcome {
        guard let captured = targets[target.id] else {
            throw DictationFailure(message: "The original text field is no longer available.", recovery: "Focus the field and dictate again.")
        }
        let resolved = try await activateAndVerify(captured)
        let outcome = InsertionOutcome(landedInSecureField: resolved.isSecureField)
        if let element = resolved.element, directTextWriter(element, text) {
            targets[target.id] = nil
            return outcome
        }
        try await paste(text)
        targets[target.id] = nil
        return outcome
    }

    func discard(_ target: TextInsertionTarget) { targets[target.id] = nil }

    /// Confirms the captured application is still frontmost and resolves the
    /// field the insertion should aim at. The application is the safety
    /// boundary — a mismatch there aborts. The field is only re-resolved:
    /// Chromium-based apps (Electron: Claude, Slack, VS Code, …) hydrate their
    /// accessibility tree lazily and rebuild nodes between capture and insert,
    /// so the captured element routinely fails identity comparison against the
    /// element that now represents the same field. Requiring identity there
    /// aborted every dictation into those apps; instead the currently focused
    /// element is adopted, keeping the paste aimed at what the user sees.
    private func activateAndVerify(_ target: CapturedTarget) async throws -> CapturedTarget {
        target.application.activate(options: [])
        try await sleep(.milliseconds(100))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else {
            throw DictationFailure(
                message: "The original application is no longer active.",
                recovery: "Focus the field and dictate again. Nothing was pasted."
            )
        }
        switch focusedElementQuery(target.application.processIdentifier) {
        case .element(let current):
            if let element = target.element, CFEqual(current, element) { return target }
            // The secure flag is sticky: a field that was secure at capture
            // stays treated as secure, and an adopted field adds its own
            // status, so a password field never leaks into History.
            return CapturedTarget(
                application: target.application,
                element: current,
                isSecureField: target.isSecureField
                    || SystemFocusedAccessibilityTargetLocator.isSecureTextElement(current)
            )
        case .none:
            // The app answers AX and states nothing is focused: a synthesized
            // paste would land nowhere while looking like a success.
            throw DictationFailure(
                message: "No text field is focused in the target application.",
                recovery: "Focus the field and dictate again. Nothing was pasted."
            )
        case .unanswered:
            // The app answers AX poorly or not at all (Electron before its
            // tree hydrates, apps without AX support). The frontmost check
            // above is the only verification available; paste keystrokes go
            // to the frontmost app regardless of AX, so proceed without a
            // field-level target.
            return CapturedTarget(application: target.application, element: nil, isSecureField: target.isSecureField)
        }
    }

    private static func systemFocusedElementQuery(for processIdentifier: pid_t) -> FocusedElementQuery {
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(processIdentifier),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        switch status {
        case .success:
            guard let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return .unanswered }
            return .element(unsafeDowncast(focusedValue, to: AXUIElement.self))
        case .noValue:
            return .none
        default:
            return .unanswered
        }
    }

    private func paste(_ text: String) async throws {
        let priorItems = pasteboard.snapshotItems()
        guard pasteboard.writeTranscription(text) else {
            pasteboard.restoreItems(priorItems)
            throw DictationFailure(message: "Could not prepare text for insertion.", recovery: "Try dictating again.")
        }
        let winterVoiceChangeCount = pasteboard.changeCount
        do {
            try postPasteKeystroke()
            try await sleep(.milliseconds(450))
        } catch {
            restore(priorItems, ifChangeCountIs: winterVoiceChangeCount)
            throw error
        }

        // Restore only if nobody changed the clipboard after WinterVoice wrote it.
        restore(priorItems, ifChangeCountIs: winterVoiceChangeCount)
    }

    private func restore(_ priorItems: [PasteboardItemSnapshot], ifChangeCountIs expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.restoreItems(priorItems)
    }

    /// Writes via AXSelectedText and confirms the write actually landed.
    /// Terminal emulators answer `.success` for this write while routing
    /// nothing to the shell, which ended the dictation "successfully" with
    /// no text on screen; an unsettable, unverifiable, or no-op write now
    /// falls through to the clipboard paste path instead.
    private static func verifiedDirectWrite(into element: AXUIElement, text: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        var beforeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &beforeValue) == .success,
              let before = beforeValue as? Int else { return false }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            return false
        }
        var afterValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &afterValue) == .success,
              let after = afterValue as? Int else { return false }
        // An unchanged character count means the write was swallowed. (A
        // caret-collapsed insertion always grows the count; dictation starts
        // from the caret, so a same-length selection replacement misreading
        // as a no-op is accepted over silently losing terminal dictations.)
        return after != before
    }

    private static func postCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw DictationFailure(message: "Could not synthesize Paste.", recovery: "Check Accessibility permission and try again.")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
