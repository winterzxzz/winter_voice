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

    init(
        targetLocator: FocusedAccessibilityTargetLocating = SystemFocusedAccessibilityTargetLocator(),
        pasteboard: PasteboardSession = SystemPasteboardSession(),
        postPasteKeystroke: (() throws -> Void)? = nil,
        sleep: ((Duration) async throws -> Void)? = nil
    ) {
        self.targetLocator = targetLocator
        self.pasteboard = pasteboard
        self.postPasteKeystroke = postPasteKeystroke ?? Self.postCommandV
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
    }

    func captureTarget() throws -> TextInsertionTarget {
        guard let focused = targetLocator.focusedTarget() else {
            throw DictationFailure(message: "No editable field is focused.", recovery: "Focus a text field and try again.")
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
        try await activateAndVerify(captured)
        let outcome = InsertionOutcome(landedInSecureField: captured.isSecureField)
        if let element = captured.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            targets[target.id] = nil
            return outcome
        }
        try await paste(text)
        targets[target.id] = nil
        return outcome
    }

    func discard(_ target: TextInsertionTarget) { targets[target.id] = nil }

    private func activateAndVerify(_ target: CapturedTarget) async throws {
        target.application.activate(options: [])
        try await sleep(.milliseconds(100))
        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        guard let element = target.element else {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else {
                throw DictationFailure(
                    message: "The original application is no longer active.",
                    recovery: "Focus the field and dictate again. Nothing was pasted."
                )
            }
            // AX never exposed the captured field, so field-level verification
            // is impossible here. Still refuse the provably wrong case: the app
            // answers AX but reports no focused element, so a synthesized paste
            // would land nowhere while looking like a success.
            var focusedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .noValue {
                throw DictationFailure(
                    message: "No text field is focused in the target application.",
                    recovery: "Focus the field and dictate again. Nothing was pasted."
                )
            }
            return
        }
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID(),
              CFEqual(focusedValue, element) else {
            throw DictationFailure(
                message: "The original text field is no longer focused.",
                recovery: "Focus the field and dictate again. Nothing was pasted."
            )
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
