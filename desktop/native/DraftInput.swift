import AppKit
import ApplicationServices
import OSLog

struct DraftActivity: Equatable {
    let keyDowns: UInt32
    let mouseDowns: [UInt32]

    static func current() -> DraftActivity {
        DraftActivity(
            keyDowns: CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown),
            mouseDowns: [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].map {
                CGEventSource.counterForEventType(.hidSystemState, eventType: $0)
            })
    }
}

@MainActor
final class DraftInput {
    enum Result { case replaced, cancelled, selectionFailed }
    enum Selection { case selected(String), cancelled, failed }
    private var prompted = false
    private let logger = Logger(subsystem: "com.wowforever.konglish.overlay", category: "chat")
    private let permission: () -> Bool
    private let modifiers: () -> CGEventFlags
    private let post: (CGEvent, pid_t) -> Void
    private let clipboard: () -> (text: String?, change: Int)
    private let writeClipboard: (String) -> Bool

    init(permission: @escaping () -> Bool = { AXIsProcessTrusted() || CGPreflightPostEventAccess() },
         modifiers: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) },
         clipboard: @escaping () -> (text: String?, change: Int) = {
             (NSPasteboard.general.string(forType: .string), NSPasteboard.general.changeCount)
         },
         writeClipboard: @escaping (String) -> Bool = {
             NSPasteboard.general.clearContents()
             return NSPasteboard.general.setString($0, forType: .string)
         },
         post: @escaping (CGEvent, pid_t) -> Void = { $0.postToPid($1) }) {
        self.permission = permission
        self.modifiers = modifiers
        self.clipboard = clipboard
        self.writeClipboard = writeClipboard
        self.post = post
    }

    func hasPermission() -> Bool {
        if permission() { return true }
        if !prompted {
            prompted = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // Games need actual modifier transitions and time to handle each key.
    // The only commands issued are Select All, Copy (to verify selection), and Paste.
    private func chord(_ key: CGKeyCode, in pid: pid_t, isCurrent: () -> Bool) async -> Bool {
        guard permission(), isCurrent(), let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        commandDown.type = .flagsChanged
        commandDown.flags = .maskCommand
        commandUp.type = .flagsChanged
        commandUp.flags = []
        down.flags = .maskCommand
        up.flags = .maskCommand
        post(commandDown, pid)
        defer { post(commandUp, pid) }
        try? await Task.sleep(for: .milliseconds(20))
        guard isCurrent() else { return false }
        post(down, pid)
        try? await Task.sleep(for: .milliseconds(30))
        post(up, pid)
        try? await Task.sleep(for: .milliseconds(30))
        return isCurrent()
    }

    func readDraft(in pid: pid_t, isCurrent: () -> Bool) async -> Selection {
        let heldKeys: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        for _ in 0..<50 {
            guard isCurrent() else { return .cancelled }
            if modifiers().intersection(heldKeys).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard isCurrent(), permission(), modifiers().intersection(heldKeys).isEmpty else { return .cancelled }
        // Let the game process the shortcut's key-up before selecting the input.
        try? await Task.sleep(for: .milliseconds(40))
        for attempt in 1...3 {
            guard isCurrent() else { return .cancelled }
            guard await chord(0, in: pid, isCurrent: isCurrent) else { return .cancelled }
            // Select All can take more than one game frame. Subsequent attempts
            // allow extra time, but only selection/copy is retried, never Paste.
            try? await Task.sleep(for: .milliseconds(40 * attempt))
            guard isCurrent() else { return .cancelled }
            let beforeCopy = clipboard().change
            guard await chord(8, in: pid, isCurrent: isCurrent) else { return .cancelled }
            for _ in 0..<15 {
                guard isCurrent() else { return .cancelled }
                if clipboard().change != beforeCopy { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let selected = clipboard()
            guard isCurrent() else { return .cancelled }
            if selected.change != beforeCopy, let text = selected.text, !Self.singleLine(text).isEmpty {
                if attempt > 1 { logger.notice("Draft selection recovered on attempt \(attempt)") }
                return .selected(text)
            }
            logger.notice("Draft selection copy missed on attempt \(attempt)")
        }
        return .failed
    }

    func replace(in pid: pid_t, original: String, translation: String, isCurrent: () -> Bool) async -> Result {
        guard !Self.singleLine(original).isEmpty, !Self.singleLine(translation).isEmpty else { return .cancelled }
        let text: String
        switch await readDraft(in: pid, isCurrent: isCurrent) {
        case .selected(let selected): text = selected
        case .cancelled: return .cancelled
        case .failed: return .selectionFailed
        }
        guard Self.singleLine(text) == Self.singleLine(original) else { return .selectionFailed }
        // Never paste without proof that the whole original draft was selected.
        guard writeClipboard(Self.singleLine(translation)), isCurrent(),
              await chord(9, in: pid, isCurrent: isCurrent) else { return .cancelled }
        return .replaced
    }
}
