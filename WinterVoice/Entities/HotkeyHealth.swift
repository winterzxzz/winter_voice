import Carbon.HIToolbox
import Foundation

struct HotkeyBinding: Codable, Equatable, Sendable {
    private static let modifierChordKeyCode: Int64 = -1
    let keyCode: Int64
    let modifiersRawValue: UInt64
    let isModifierOnly: Bool

    static let function = HotkeyBinding(
        keyCode: Int64(kVK_Function),
        modifiers: .maskSecondaryFn,
        isModifierOnly: true
    )
    static let rightOption = HotkeyBinding(
        keyCode: Int64(kVK_RightOption), modifiers: .maskAlternate, isModifierOnly: true
    )
    static let rightControl = HotkeyBinding(
        keyCode: Int64(kVK_RightControl), modifiers: .maskControl, isModifierOnly: true
    )
    static let leftControl = HotkeyBinding(
        keyCode: Int64(kVK_Control), modifiers: .maskControl, isModifierOnly: true
    )

    static func modifierChord(_ modifiers: CGEventFlags) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: modifierChordKeyCode,
            modifiers: modifiers,
            isModifierOnly: true
        )
    }

    init(keyCode: Int64, modifiers: CGEventFlags, isModifierOnly: Bool) {
        self.keyCode = keyCode
        modifiersRawValue = modifiers.intersection(.hotkeyModifiers).rawValue
        self.isModifierOnly = isModifierOnly
    }

    var modifiers: CGEventFlags { CGEventFlags(rawValue: modifiersRawValue) }

    var title: String {
        if isModifierOnly {
            return keyCode == Self.modifierChordKeyCode
                ? Self.modifierSymbols(modifiers)
                : Self.modifierKeyTitle(keyCode)
        }
        return Self.modifierSymbols(modifiers) + Self.keyTitle(keyCode)
    }

    /// The binding rendered as discrete keycap labels, e.g. ["Cmd", "Shift", "Space"],
    /// or ["Fn / Globe"] for a single named modifier key.
    var keyLabels: [String] {
        if isModifierOnly, keyCode != Self.modifierChordKeyCode {
            return [Self.modifierKeyTitle(keyCode)]
        }
        var labels = Self.modifierLabels(modifiers)
        if !isModifierOnly {
            labels.append(Self.keyTitle(keyCode))
        }
        return labels.isEmpty ? [title] : labels
    }

    private static func modifierLabels(_ flags: CGEventFlags) -> [String] {
        var value: [String] = []
        if flags.contains(.maskControl) { value.append("Ctrl") }
        if flags.contains(.maskAlternate) { value.append("Opt") }
        if flags.contains(.maskShift) { value.append("Shift") }
        if flags.contains(.maskCommand) { value.append("Cmd") }
        if flags.contains(.maskSecondaryFn) { value.append("Fn") }
        return value
    }

    func matchesKeyEvent(keyCode: Int64, flags: CGEventFlags) -> Bool {
        !isModifierOnly && self.keyCode == keyCode
            && flags.intersection(.hotkeyModifiers) == modifiers
    }

    func matchesModifierEvent(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard isModifierOnly else { return false }
        if self.keyCode == Self.modifierChordKeyCode {
            let active = flags.intersection(.hotkeyModifiers)
            return active.intersection(modifiers) == modifiers
        }
        guard self.keyCode == keyCode else { return false }
        if self.keyCode == Int64(kVK_Function) {
            return flags.contains(.maskSecondaryFn)
        }
        if let deviceSides = Self.deviceSideFlags(for: self.keyCode) {
            let physical = flags.intersection([deviceSides.left, deviceSides.right])
            if !physical.isEmpty {
                return physical.contains(deviceSides.selected)
            }
        }
        return !flags.intersection(modifiers).isEmpty
    }

    static func recorded(keyCode: Int64, flags: CGEventFlags) -> HotkeyBinding {
        let modifier = modifierMask(for: keyCode)
        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifier ?? flags,
            isModifierOnly: modifier != nil
        )
    }

    static func isModifierKey(_ keyCode: Int64) -> Bool {
        modifierMask(for: keyCode) != nil
    }

    private static func modifierMask(for keyCode: Int64) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Function: .maskSecondaryFn
        case kVK_Option, kVK_RightOption: .maskAlternate
        case kVK_Control, kVK_RightControl: .maskControl
        case kVK_Command, kVK_RightCommand: .maskCommand
        case kVK_Shift, kVK_RightShift: .maskShift
        default: nil
        }
    }

    private static func deviceSideFlags(
        for keyCode: Int64
    ) -> (left: CGEventFlags, right: CGEventFlags, selected: CGEventFlags)? {
        switch Int(keyCode) {
        case kVK_Option:
            let left = CGEventFlags(rawValue: 0x20), right = CGEventFlags(rawValue: 0x40)
            return (left, right, left)
        case kVK_RightOption:
            let left = CGEventFlags(rawValue: 0x20), right = CGEventFlags(rawValue: 0x40)
            return (left, right, right)
        case kVK_Control:
            let left = CGEventFlags(rawValue: 0x1), right = CGEventFlags(rawValue: 0x2000)
            return (left, right, left)
        case kVK_RightControl:
            let left = CGEventFlags(rawValue: 0x1), right = CGEventFlags(rawValue: 0x2000)
            return (left, right, right)
        case kVK_Command:
            let left = CGEventFlags(rawValue: 0x8), right = CGEventFlags(rawValue: 0x10)
            return (left, right, left)
        case kVK_RightCommand:
            let left = CGEventFlags(rawValue: 0x8), right = CGEventFlags(rawValue: 0x10)
            return (left, right, right)
        default:
            return nil
        }
    }

    private static func modifierKeyTitle(_ keyCode: Int64) -> String {
        switch Int(keyCode) {
        case kVK_Function: "Fn / Globe"
        case kVK_Option: "Left Option"
        case kVK_RightOption: "Right Option"
        case kVK_Control: "Left Control"
        case kVK_RightControl: "Right Control"
        case kVK_Command: "Left Command"
        case kVK_RightCommand: "Right Command"
        case kVK_Shift: "Left Shift"
        case kVK_RightShift: "Right Shift"
        default: "Key \(keyCode)"
        }
    }

    private static func modifierSymbols(_ flags: CGEventFlags) -> String {
        var value = ""
        if flags.contains(.maskControl) { value += "⌃" }
        if flags.contains(.maskAlternate) { value += "⌥" }
        if flags.contains(.maskShift) { value += "⇧" }
        if flags.contains(.maskCommand) { value += "⌘" }
        if flags.contains(.maskSecondaryFn) { value += "fn " }
        return value
    }

    private static func keyTitle(_ keyCode: Int64) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Escape: "Escape"
        case kVK_Delete: "Delete"
        case kVK_ForwardDelete: "Fwd Delete"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "Page Up"
        case kVK_PageDown: "Page Down"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Help: "Help"
        case 0x6E: "Menu"
        default: namedKeys[Int(keyCode)] ?? "Key \(keyCode)"
        }
    }

    private static let namedKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}

extension CGEventFlags {
    static let hotkeyModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn
    ]
}

enum RecordingMode: String, CaseIterable, Codable, Sendable {
    case holdToTalk
    case toggle

    var title: String { self == .holdToTalk ? "Hold to Talk" : "Toggle" }

    func instruction(binding: HotkeyBinding) -> String {
        switch self {
        case .holdToTalk: "Hold \(binding.title) to record and release it to transcribe."
        case .toggle: "Press \(binding.title) to start recording and press it again to transcribe."
        }
    }
}

enum HotkeyHealth: Equatable, Sendable {
    case permissionRequired
    case listening
    case installationFailed

    func title(binding: HotkeyBinding) -> String {
        switch self {
        case .permissionRequired: "Input Monitoring required"
        case .listening: "Listening for \(binding.title)"
        case .installationFailed: "Hotkey unavailable"
        }
    }

    func detail(binding: HotkeyBinding, mode: RecordingMode = .holdToTalk) -> String {
        switch self {
        case .permissionRequired:
            "Allow WinterVoice in Privacy & Security → Input Monitoring, then return to WinterVoice."
        case .listening:
            mode.instruction(binding: binding)
        case .installationFailed:
            "WinterVoice could not install or recover its global hotkey listener. Return to the app to retry."
        }
    }
}
