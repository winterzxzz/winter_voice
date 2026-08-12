import AppKit

@MainActor
final class SystemTextInjector: TextInjecting {
    private struct CapturedTarget {
        let application: NSRunningApplication
        let element: AXUIElement
    }

    private struct PasteboardItemSnapshot {
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

    private var targets: [UUID: CapturedTarget] = [:]

    func captureTarget() throws -> TextInsertionTarget {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw DictationFailure(message: "No target application was found.", recovery: "Focus a text field and try again.")
        }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw DictationFailure(message: "No editable field is focused.", recovery: "Focus a text field and try again.")
        }
        let id = UUID()
        targets[id] = CapturedTarget(application: app, element: unsafeDowncast(value, to: AXUIElement.self))
        return TextInsertionTarget(id: id)
    }

    func insert(_ text: String, into target: TextInsertionTarget) async throws {
        guard let captured = targets[target.id] else {
            throw DictationFailure(message: "The original text field is no longer available.", recovery: "Focus the field and dictate again.")
        }
        try await activateAndVerify(captured)
        if AXUIElementSetAttributeValue(captured.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            targets[target.id] = nil
            return
        }
        try await paste(text, into: captured)
        targets[target.id] = nil
    }

    func discard(_ target: TextInsertionTarget) { targets[target.id] = nil }

    private func activateAndVerify(_ target: CapturedTarget) async throws {
        target.application.activate(options: [])
        try await Task.sleep(for: .milliseconds(100))
        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID(),
              CFEqual(focusedValue, target.element) else {
            throw DictationFailure(
                message: "The original text field is no longer focused.",
                recovery: "Focus the field and dictate again. Nothing was pasted."
            )
        }
    }

    private func paste(_ text: String, into target: CapturedTarget) async throws {
        let pasteboard = NSPasteboard.general
        let priorItems = (pasteboard.pasteboardItems ?? []).map(PasteboardItemSnapshot.init)
        pasteboard.clearContents()
        var winterVoiceChangeCount = pasteboard.changeCount
        guard pasteboard.setString(text, forType: .string) else {
            restore(priorItems, on: pasteboard, ifChangeCountIs: winterVoiceChangeCount)
            throw DictationFailure(message: "Could not prepare text for insertion.", recovery: "Try dictating again.")
        }
        winterVoiceChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            restore(priorItems, on: pasteboard, ifChangeCountIs: winterVoiceChangeCount)
            throw DictationFailure(message: "Could not synthesize Paste.", recovery: "Check Accessibility permission and try again.")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            restore(priorItems, on: pasteboard, ifChangeCountIs: winterVoiceChangeCount)
            throw error
        }

        // Restore only if nobody changed the clipboard after WinterVoice wrote it.
        restore(priorItems, on: pasteboard, ifChangeCountIs: winterVoiceChangeCount)
    }

    private func restore(
        _ priorItems: [PasteboardItemSnapshot],
        on pasteboard: NSPasteboard,
        ifChangeCountIs expectedChangeCount: Int
    ) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.clearContents()
        if !priorItems.isEmpty { pasteboard.writeObjects(priorItems.map { $0.makeItem() }) }
    }
}
