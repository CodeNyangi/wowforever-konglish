import AppKit

@main
struct OverlayChecks {
    static func main() throws {
        let message = "[12:30] [Party] [Tank]: Mana break after this pull?"
        precondition(chatBodyRange(message).map { String(message[$0]) } == "Mana break after this pull?")
        precondition(chatBodyRange("Someone yells: Stack on me.") != nil)
        let whisper = "[Healer-Realm] whispers: Ready?"
        precondition(chatBodyRange(whisper).map { String(whisper[$0]) } == "Ready?")
        let korean = "[파티] [친구]: 준비됐어요."
        precondition(chatBodyRange(korean).map { String(korean[$0]) } == "준비됐어요.")
        precondition(chatBodyRange("General") == nil)
        precondition(chatBodyRange("Combat Log") == nil)
        let named = "[1. General - Dun Morogh] [Tank]: Meet me outside."
        precondition(chatBodyRange(named).map { String(named[$0]) } == "Meet me outside.")
        let leadingGlyph = "] [1. General - Dun Morogh] [Tank]: Meet me outside."
        precondition(chatBodyRange(leadingGlyph).map { String(leadingGlyph[$0]) } == "Meet me outside.")
        precondition(chatBodyRange("[1. General - Dun Morogh]: text in the input") == nil)
        let imperfect = "[1. General - Dun Moroghi [Tankl: There is"
        precondition(chatBodyRange(imperfect).map { String(imperfect[$0]) } == "There is")
        let approximate = "(r.Gensrar- Dun Morogh (Tankl: There is"
        precondition(chatBodyRange(approximate).map { String(approximate[$0]) } == "There is")

        func textLine(_ text: String, x: CGFloat = 43, y: CGFloat, bodyX: CGFloat? = nil) -> ChatTextLine {
            ChatTextLine(text: text, bounds: CGRect(x: x, y: y, width: 245, height: 16),
                         bodyBounds: bodyX.map { CGRect(x: $0, y: y, width: 82, height: 16) })
        }
        let messageLines = [
            textLine("General", y: 104),
            textLine("Combat Log", x: 120, y: 104),
            textLine("Looking for more, pst.", x: 58, y: 142),
            textLine("[1. General - Dun Morogh] [Tank]: There is", y: 166, bodyX: 350),
            textLine("a forge in Kharanos. It is across the", x: 58, y: 190),
            textLine("street from the inn.", x: 58, y: 214),
            textLine("[1. General - Dun Morogh] [Healer]: Thanks", y: 238, bodyX: 350),
            textLine("everyone", x: 58, y: 262),
        ]
        let grouped = groupChat(messageLines)
        precondition(grouped.map(\.body) == [
            "Looking for more, pst.", "There is a forge in Kharanos. It is across the street from the inn.", "Thanks everyone",
        ])
        precondition(grouped.map { $0.segments.count } == [1, 3, 2])
        precondition(grouped[1].bounds.minY == 214)
        precondition(grouped.map(\.target) == ["ko", "ko", "ko"])
        let batch = groupChat([
            textLine("[1. General - Dun Morogh] [Tank]: There is", y: 94, bodyX: 350),
            textLine("a forge in Kharanos. It is across the", x: 58, y: 118),
            textLine("street from the inn.", x: 58, y: 142),
            textLine("[1. General - Dun Morogh] [Tank]: Meet", y: 166, bodyX: 350),
            textLine("me outside.", x: 58, y: 190),
            textLine("[1. General - Dun Morogh] [Healer]: I'm ready.", y: 214, bodyX: 350),
        ])
        precondition(batch.map(\.body) == [grouped[1].body, "Meet me outside.", "I'm ready."])
        let flushWrapped = groupChat([
            textLine("[Party] [Tank]: Looking for", x: 44, y: 100, bodyX: 180),
            textLine("[Shadow Wand] for my friend", x: 42, y: 124),
            textLine("and a bag if you have one.", x: 43, y: 148),
            textLine("[Party] [Healer]: I have one.", x: 43, y: 172, bodyX: 190),
        ])
        precondition(flushWrapped.map(\.body) == ["Looking for [Shadow Wand] for my friend and a bag if you have one.", "I have one."])
        precondition(flushWrapped.map { $0.segments.count } == [3, 1])
        let smallOCR = groupChat([
            ChatTextLine(text: "[Tank]: Meet me", bounds: CGRect(x: 43, y: 100, width: 180, height: 10),
                         bodyBounds: CGRect(x: 110, y: 100, width: 113, height: 10)),
            ChatTextLine(text: "at the inn, please.", bounds: CGRect(x: 43, y: 128, width: 180, height: 10), bodyBounds: nil),
        ])
        precondition(smallOCR.map(\.body) == ["Meet me at the inn, please."])
        var batchRows = ChatRows()
        batchRows.replace(with: grouped)
        let wrappedID = batchRows.rows[1].id
        batchRows.update(wrappedID, to: .translated("여관 맞은편에 대장간이 있어요."))
        batchRows.replace(with: batch)
        precondition(batchRows.rows[0].id == wrappedID)
        precondition(batchRows.rows[0].state == .translated("여관 맞은편에 대장간이 있어요."))
        precondition(batchRows.rows[0].visibleSegments.map(\.minY) == [94, 118, 142])
        let unprefixed = groupChat([
            textLine("Combat Log", y: 90),
            textLine("You have discovered Anvilmar.", y: 114),
            textLine("You receive loot: Hearthstone.", y: 138),
        ])
        precondition(unprefixed.map(\.body) == ["You have discovered Anvilmar.", "You receive loot: Hearthstone."])
        let crowded = (0..<18).map { index in textLine("System message \(index)", y: CGFloat(index * 22)) }
        precondition(groupChat(crowded).count == 18)
        precondition(groupChat([textLine("[Tank]", y: 100)]).isEmpty)
        precondition(groupChat([textLine("1. General - Dun Morogh [Tank", y: 100)]).isEmpty)

        let headerOnly = "[1. General - Dun Morogh] [Tank]:"
        let separated = groupChat([
            ChatTextLine(text: headerOnly, bounds: CGRect(x: 43, y: 100, width: 350, height: 11), bodyBounds: nil),
            ChatTextLine(text: "Not in this game", bounds: CGRect(x: 56, y: 122, width: 140, height: 11), bodyBounds: nil),
            ChatTextLine(text: "that is retail.", bounds: CGRect(x: 56, y: 144, width: 110, height: 11), bodyBounds: nil),
            ChatTextLine(text: headerOnly, bounds: CGRect(x: 43, y: 166, width: 280, height: 11), bodyBounds: nil),
            ChatTextLine(text: "준비되면 시작해요.", bounds: CGRect(x: 333, y: 168, width: 95, height: 10), bodyBounds: nil),
            textLine("[1. General - Dun Morogh]: 마나 좀 채우고 갈게요.", y: 225, bodyX: 250),
        ], draftAfterY: 208)
        precondition(separated.map(\.body) == ["Not in this game that is retail.", "준비되면 시작해요.", "마나 좀 채우고 갈게요."])
        precondition(separated.map(\.target) == ["ko", "en", "en"])
        precondition(separated.map(\.isDraft) == [false, false, true])
        let draftLines = [
            textLine("[1. General - Dun Morogh] [Tank]: 준비됐어요.", y: 110, bodyX: 350),
            ChatTextLine(text: "[1. General - Dun Morogh]:", bounds: CGRect(x: 45, y: 144, width: 210, height: 17), bodyBounds: nil),
            ChatTextLine(text: "마나 좀 채우고 갈게요.", bounds: CGRect(x: 260, y: 145, width: 140, height: 16), bodyBounds: nil),
        ]
        precondition(draftText(from: draftLines) == "마나 좀 채우고 갈게요.")
        precondition(draftText(from: Array(draftLines.prefix(1))) == nil)

        func line(_ text: String, y: CGFloat) -> ChatObservation {
            ChatObservation(line: text, body: text, bounds: CGRect(x: 20, y: y, width: 150, height: 12))
        }
        var rows = ChatRows()
        rows.replace(with: [line("one", y: 50), line("two", y: 66)])
        let first = rows.rows[0]
        let second = rows.rows[1]
        precondition(rows.confirm(second.id, near: second.observation.bounds) != nil)
        rows.update(second.id, to: .translated("둘"))
        rows.replace(with: [line("two", y: 50), line("three", y: 66)])
        precondition(rows.row(first.id) == nil)
        precondition(rows.confirm(second.id, near: second.observation.bounds) == nil)
        precondition(rows.rows[0].state == .translated("둘"))
        rows.replace(with: [line("two", y: 50), line("two", y: 66)])
        precondition(rows.row(second.id) == nil)
        precondition(rows.rows.allSatisfy { $0.state == .original })
        let repeated = rows.rows.map(\.id)
        rows.replace(with: [line("two", y: 50), line("two", y: 66)])
        precondition(rows.rows.map(\.id) == repeated)

        var stable = ChatRows()
        stable.replace(with: [line("Original", y: 70)])
        let original = stable.rows[0]
        stable.update(original.id, to: .translated("번역"))
        stable.replace(with: [line("original", y: 71)])
        precondition(stable.rows[0].visibleSegments == original.visibleSegments)
        stable.replace(with: [])
        precondition(stable.rows[0].id == original.id && stable.rows[0].state == .translated("번역"))
        precondition(stable.confirm(original.id, near: original.observation.bounds) == nil)
        stable.replace(with: [line("replacement", y: 71)])
        precondition(stable.row(original.id) == nil && stable.rows[0].state == .original)
        stable.replace(with: [])
        stable.replace(with: [])
        precondition(stable.rows.isEmpty)

        let window = CGSize(width: 650, height: 400)
        let area = CGRect(x: 20, y: 120, width: 500, height: 50)
        let region = ChatRegion(rect: area, windowSize: window)
        precondition(region.fits(window))
        precondition(!region.fits(CGSize(width: 540, height: 400)))

        let fixture = NSImage(size: window, flipped: true) { rect in
            NSColor.black.setFill()
            rect.fill()
            let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white]
            ("Private text outside the chat area" as NSString).draw(at: CGPoint(x: 24, y: 30), withAttributes: style)
            ("[Party] [Tank]: Mana break after this pull?" as NSString)
                .draw(at: CGPoint(x: 24, y: 128), withAttributes: style)
            return true
        }
        var box = CGRect(origin: .zero, size: window)
        guard let image = fixture.cgImage(forProposedRect: &box, context: nil, hints: nil),
              let cropped = cropChat(image, region: area, windowSize: window) else { fatalError("Could not crop test image") }
        let recognized = try recognizeChat(cropped, area: area)
        precondition(recognized.count == 1 && recognized[0].body == "Mana break after this pull?",
                     "OCR did not isolate the body: \(recognized.map(\.body))")
        precondition(recognized[0].bounds.minX > 95 && area.contains(recognized[0].bounds),
                     "OCR did not find the body position")
        let koFixture = NSImage(size: window, flipped: true) { rect in
            NSColor.black.setFill()
            rect.fill()
            let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white]
            ("[Party] [Tank]: 준비되면 시작해요." as NSString)
                .draw(at: CGPoint(x: 24, y: 128), withAttributes: style)
            return true
        }
        guard let koImage = koFixture.cgImage(forProposedRect: &box, context: nil, hints: nil),
              let koCrop = cropChat(koImage, region: area, windowSize: window) else { fatalError("Could not crop Korean test image") }
        let recognizedKorean = try recognizeChat(koCrop, area: area)
        precondition(recognizedKorean.first?.target == "en"
            && recognizedKorean.first?.body == "준비되면 시작해요.",
            "OCR did not recognize Korean: \(recognizedKorean.map(\.body))")
        let draftFixture = NSImage(size: window, flipped: true) { rect in
            NSColor.black.setFill()
            rect.fill()
            let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white]
            ("Say: 여관 앞에서 만나요." as NSString).draw(at: CGPoint(x: 24, y: 182), withAttributes: style)
            return true
        }
        guard let draftImage = draftFixture.cgImage(forProposedRect: &box, context: nil, hints: nil) else { fatalError("No draft fixture image") }
        let inputArea = draftArea(near: area, windowSize: window)
        let croppedDraft = cropChat(draftImage, region: inputArea, windowSize: window)!
        let capturedDraft = try recognizeDraft(croppedDraft, area: inputArea)
        precondition(capturedDraft == "여관 앞에서 만나요.", "OCR missed the input below the selection: \(capturedDraft ?? "")")

        let motionArea = CGRect(x: 0, y: 0, width: 530, height: 360)
        let sample = ["Can you wait at the bridge?", "The healer is out of mana.",
                      "Let's meet next to the inn.", "The road ahead looks clear.", "Keep an eye on the patrol."]
        func motionFrame(offset: CGFloat, background: CGFloat, words: [String]) -> ChatMotionFrame {
            let image = NSImage(size: motionArea.size, flipped: true) { rect in
                NSColor(white: background, alpha: 1).setFill()
                rect.fill()
                let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white]
                for (index, line) in words.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 35, y: 75 + CGFloat(index) * 44 + offset), withAttributes: style)
                }
                return true
            }
            var bounds = motionArea
            return ChatMotionFrame(image: image.cgImage(forProposedRect: &bounds, context: nil, hints: nil)!, area: motionArea)!
        }
        let anchors = sample.indices.map { CGRect(x: 35, y: 75 + CGFloat($0) * 44, width: 230, height: 24) }
        let originalFrame = motionFrame(offset: 0, background: 0.17, words: sample)
        for offset: CGFloat in [0, -22, -66, -88, 44] {
            let newer = motionFrame(offset: offset, background: 0.32, words: sample)
            let shift = originalFrame.shift(to: newer, anchors: anchors, in: motionArea)
            precondition(shift.map { abs($0 - offset) <= 2 } == true, "Chat offset \(offset) measured \(String(describing: shift))")
        }
        let otherTab = motionFrame(offset: 0, background: 0.26, words: ["A new window", "Several unrelated strings", "Another message entirely"])
        precondition(originalFrame.shift(to: otherTab, anchors: anchors, in: motionArea) == nil)
        print("Overlay checks passed: tabs, wrapped messages, OCR crop, rapid scroll tracking, missed frames, and window resizing.")
    }
}
