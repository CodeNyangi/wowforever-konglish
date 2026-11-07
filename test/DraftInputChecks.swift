import AppKit

@main
struct DraftInputChecks {
    @MainActor static func main() async {
        let original = "여관 앞에서 만나요"
        let english = "Meet me in front of the inn."
        var field = original
        var selected = false
        var commandHeld = false
        var current = true
        var allowed = true
        var held: CGEventFlags = []
        var selectionWorks = true
        var copyWorks = true
        var changeAfterSelect = false
        var clipboardText = "previous clipboard"
        var clipboardChange = 1
        var keys: [Int64] = []
        var targetPIDs: [pid_t] = []
        let input = DraftInput(permission: { allowed }, modifiers: { held },
                               clipboard: { (clipboardText, clipboardChange) },
                               writeClipboard: { clipboardText = $0; clipboardChange += 1; return true }) { event, pid in
            targetPIDs.append(pid)
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if event.type == .flagsChanged {
                commandHeld = event.flags.contains(.maskCommand)
                return
            }
            guard event.type == .keyUp else { return }
            keys.append(key)
            // Model a game that requires a real Command key transition.
            guard commandHeld else { return }
            switch key {
            case 0:
                selected = selectionWorks
                if changeAfterSelect { current = false }
            case 8:
                if selected && copyWorks { clipboardText = field; clipboardChange += 1 }
            case 9:
                field = selected ? clipboardText : field + clipboardText
                selected = false
            default: preconditionFailure("Never send Return or gameplay keys.")
            }
        }
        switch await input.readDraft(in: 123, isCurrent: { current }) {
        case .selected(let text): precondition(text == original, "Translate the exact input text, not a second OCR guess.")
        default: preconditionFailure("Could not read the full draft.")
        }
        keys.removeAll()
        targetPIDs.removeAll()
        let replaced = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(replaced == .replaced && field == english && !field.contains(original))
        precondition(keys == [0, 8, 9] && targetPIDs.allSatisfy { $0 == 123 } && !commandHeld)

        func reset() {
            field = original; selected = false; keys = []; targetPIDs = []
            current = true; selectionWorks = true; copyWorks = true; changeAfterSelect = false
        }
        reset()
        selectionWorks = false
        let appended = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(appended == .selectionFailed && field == original && !keys.contains(9),
                     "If Select All is ignored by the game, do not append or touch the draft.")
        reset()
        clipboardText = original
        copyWorks = false
        let staleClipboard = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(staleClipboard == .selectionFailed && field == original && !keys.contains(9),
                     "Previously copied identical text is not proof of a current selection.")
        reset()
        field = "여관 앞에서 만나요 추가로 쓴 내용"
        let mismatch = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(mismatch == .selectionFailed && !keys.contains(9), "Never replace a different or longer draft.")
        reset()
        current = false
        let stale = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(stale == .cancelled && targetPIDs.isEmpty)
        reset()
        changeAfterSelect = true
        let interrupted = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(interrupted == .cancelled && keys == [0] && !commandHeld && field == original,
                     "Changing focus must release Command and cancel before paste.")
        reset()
        allowed = false
        let denied = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(denied == .cancelled && targetPIDs.isEmpty)
        allowed = true
        held = [.maskCommand, .maskShift]
        let unreleased = await input.replace(in: 123, original: original, translation: english, isCurrent: { current })
        precondition(unreleased == .cancelled && targetPIDs.isEmpty)
        precondition(DraftInput.singleLine(" Meet\r\nme\tat the inn.\u{2028} ") == "Meet me at the inn.")
        print("Draft input checks passed: replace without appending, failed/stale selection, changed draft/focus, modifier cleanup, permission, and no Enter.")
    }
}
