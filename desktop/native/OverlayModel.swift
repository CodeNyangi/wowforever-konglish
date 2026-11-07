import Foundation
import CoreGraphics
import Vision

struct ChatRegion: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let windowWidth: Double
    let windowHeight: Double

    init(rect: CGRect, windowSize: CGSize) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
        windowWidth = windowSize.width
        windowHeight = windowSize.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    func fits(_ windowSize: CGSize) -> Bool {
        abs(windowSize.width - windowWidth) < 2 && abs(windowSize.height - windowHeight) < 2
            && x >= 0 && y >= 0 && width >= 100 && height >= 24
            && x + width <= windowSize.width && y + height <= windowSize.height
    }
}

struct ChatObservation {
    let line: String
    let body: String
    var segments: [CGRect]
    let isDraft: Bool

    init(line: String, body: String, bounds: CGRect, isDraft: Bool = false) {
        self.line = line
        self.body = body
        segments = [bounds]
        self.isDraft = isDraft
    }

    var bounds: CGRect { segments[segments.count - 1] }
    var key: String {
        (isDraft ? "draft:" : "chat:") + body.lowercased()
            .replacingOccurrences(of: "[’‘]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var target: String {
        body.range(of: #"\p{Hangul}"#, options: .regularExpression) == nil ? "ko" : "en"
    }
}

private let chatPrefix = try! NSRegularExpression(pattern:
    #"^\s*(?:\[?\d{1,2}:\d{2}(?::\d{2})?\]?\s+)?(?:(?:to\s+)?(?:[\[(][^\[\]()\n]+[\])]?\s*)*[\[(](?!\d+\s*\.\s|(?:party|guild|raid|general|instance(?: chat)?|combat log)[\])])[^\[\]():\n]+?[\])lIijJ|]\s*(?:(?:says|yells|whispers)\s*)?|[\p{L}\p{N}'\-]+(?:\s+[\p{L}\p{N}'\-]+){0,2}\s+(?:says|yells|whispers))\s*[:：]\s*"#,
    options: .caseInsensitive
)

private func chatPrefixEnd(_ line: String) -> String.Index? {
    chatPrefix.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        .flatMap { Range($0.range, in: line)?.upperBound }
}

private let draftPrefix = try! NSRegularExpression(pattern:
    #"^\s*(?:[\[(]?\d+\s*\.\s+[^\[\]()\n:]+[\])]?|[\[(]?(?:say|party|raid|guild|officer|yell|instance(?: chat)?)[\])]?|(?:whisper\s+)?to\s+[^:\n]+)\s*[:：]\s*"#,
    options: .caseInsensitive
)

private func draftBodyRange(_ line: String) -> Range<String.Index>? {
    guard let match = draftPrefix.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
          let end = Range(match.range, in: line)?.upperBound,
          line[end...].range(of: #"[A-Za-z\p{Hangul}]"#, options: .regularExpression) != nil,
          let last = line.lastIndex(where: { !$0.isWhitespace }) else { return nil }
    return end..<line.index(after: last)
}

func chatBodyRange(_ line: String) -> Range<String.Index>? {
    guard let start = chatPrefixEnd(line) else { return nil }
    let candidate = line[start...]
    guard let first = candidate.firstIndex(where: { !$0.isWhitespace }),
          let last = candidate.lastIndex(where: { !$0.isWhitespace }),
          candidate.range(of: #"[A-Za-z0-9\p{Hangul}]"#, options: .regularExpression) != nil else { return nil }
    return first..<line.index(after: last)
}

struct ChatTextLine {
    let text: String
    let bounds: CGRect
    let bodyBounds: CGRect?
}

func groupChat(_ recognized: [ChatTextLine], draftAfterY: CGFloat? = nil) -> [ChatObservation] {
    var messages: [ChatObservation] = []
    var header: ChatTextLine?
    var previous: CGRect?
    var message: ChatObservation?

    func beginPlain(_ line: ChatTextLine, text: String) {
        guard !["general", "combat log"].contains(text.lowercased()),
              !looksLikeHeader(text),
              text.range(of: #"[A-Za-z\p{Hangul}]"#, options: .regularExpression) != nil,
              draftPrefix.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { return }
        message = ChatObservation(line: text, body: text, bounds: line.bounds)
        header = line
        previous = line.bounds
    }

    let sorted = recognized.sorted { $0.bounds.midY < $1.bounds.midY }
    var visualRows: [[ChatTextLine]] = []
    for line in sorted {
        if let first = visualRows.last?.first,
           abs(line.bounds.midY - first.bounds.midY) <= min(7, first.bounds.height * 0.45) {
            visualRows[visualRows.count - 1].append(line)
        } else {
            visualRows.append([line])
        }
    }

    for line in visualRows.flatMap({ $0.sorted { $0.bounds.minX < $1.bounds.minX } }) {
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)
        if let draftAfterY, line.bounds.midY >= draftAfterY,
           let range = draftBodyRange(line.text), let bounds = line.bodyBounds {
            if let message { messages.append(message) }
            messages.append(ChatObservation(line: line.text, body: String(line.text[range]), bounds: bounds, isDraft: true))
            message = nil
            header = nil
            previous = nil
        } else if chatPrefixEnd(line.text) != nil {
            if let message { messages.append(message) }
            message = nil
            if let bodyBounds = line.bodyBounds, let range = chatBodyRange(line.text) {
                message = ChatObservation(line: line.text, body: String(line.text[range]), bounds: bodyBounds)
            }
            header = line
            previous = line.bounds
        } else if let head = header, let last = previous {
            let indent = line.bounds.minX - head.bounds.minX
            let spacing = line.bounds.midY - last.midY
            let lineHeight = max(last.height, line.bounds.height)
            let adjacent = abs(spacing) <= min(7, lineHeight * 0.5) && line.bounds.minX >= last.maxX - 4
            let wrapped = (2.5...62).contains(indent)
                && (lineHeight * 0.50...max(26, lineHeight * 1.9)).contains(spacing)
            if (adjacent || wrapped),
               trimmed.range(of: #"[A-Za-z0-9\p{Hangul}]"#, options: .regularExpression) != nil,
               !looksLikeHeader(trimmed) {
                if let current = message {
                    var combined = ChatObservation(line: current.line + " " + trimmed,
                                                   body: current.body + " " + trimmed, bounds: line.bounds)
                    combined.segments = adjacent
                        ? Array(current.segments.dropLast()) + [current.bounds.union(line.bounds)]
                        : current.segments + [line.bounds]
                    message = combined
                } else {
                    message = ChatObservation(line: head.text + " " + trimmed, body: trimmed, bounds: line.bounds)
                }
                previous = line.bounds
            } else if spacing > min(7, lineHeight * 0.5) {
                if let message { messages.append(message) }
                message = nil
                header = nil
                previous = nil
                beginPlain(line, text: trimmed)
            }
        } else {
            beginPlain(line, text: trimmed)
        }
    }
    if let message { messages.append(message) }
    return messages
}

private func looksLikeHeader(_ text: String) -> Bool {
    text.range(of: #"^(?:[\[(]|\d+\s*\.\s)"#, options: .regularExpression) != nil
}

private func recognizeLines(_ image: CGImage, area: CGRect) throws -> [ChatTextLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "ko-KR"]
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])

    func position(_ bounds: CGRect) -> CGRect {
        CGRect(x: area.minX + bounds.minX * area.width, y: area.minY + (1 - bounds.maxY) * area.height,
               width: bounds.width * area.width, height: bounds.height * area.height)
    }

    return (request.results ?? []).compactMap { observation -> ChatTextLine? in
        guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
        let bounds = position(observation.boundingBox)
        let draftAfterY = area.maxY - 42
        let range = chatBodyRange(candidate.string)
            ?? (bounds.midY >= draftAfterY ? draftBodyRange(candidate.string) : nil)
        let bodyBounds = range
            .flatMap { try? candidate.boundingBox(for: $0)?.boundingBox }
            .map(position)
        return ChatTextLine(text: candidate.string, bounds: bounds, bodyBounds: bodyBounds)
    }
}

func recognizeChat(_ image: CGImage, area: CGRect) throws -> [ChatObservation] {
    groupChat(try recognizeLines(image, area: area), draftAfterY: area.maxY - 42)
}

func draftText(from lines: [ChatTextLine]) -> String? {
    for label in lines.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
        guard draftPrefix.firstMatch(in: label.text, range: NSRange(label.text.startIndex..., in: label.text)) != nil else { continue }
        let following = lines.filter {
            abs($0.bounds.midY - label.bounds.midY) <= 7 && $0.bounds.minX >= label.bounds.maxX - 3
        }.sorted { $0.bounds.minX < $1.bounds.minX }
        let text = ([label.text] + following.map(\.text)).joined(separator: " ")
        if let range = draftBodyRange(text), text[range].range(of: #"\p{Hangul}"#, options: .regularExpression) != nil {
            return String(text[range])
        }
    }
    return nil
}

func draftArea(near region: CGRect, windowSize: CGSize) -> CGRect {
    let top = max(region.minY, region.maxY - 44)
    let bottom = min(windowSize.height, region.maxY + 55)
    return CGRect(x: region.minX, y: top, width: region.width, height: bottom - top)
}

func recognizeDraft(_ crop: CGImage, area: CGRect) throws -> String? {
    draftText(from: try recognizeLines(crop, area: area))
}

struct ChatRow {
    enum State: Equatable {
        case original
        case waiting
        case translated(String)
        case failed
    }
    let id: Int
    var observation: ChatObservation
    var visibleSegments: [CGRect]
    var missedFrames = 0
    var state: State = .original

    init(id: Int, observation: ChatObservation) {
        self.id = id
        self.observation = observation
        visibleSegments = observation.segments
    }
}

struct ChatRows {
    private(set) var rows: [ChatRow] = []
    private var nextID = 0

    mutating func replace(with visible: [ChatObservation]) {
        let previous = Dictionary(grouping: rows, by: { $0.observation.key })
        let counts = Dictionary(grouping: visible, by: \.key).mapValues(\.count)
        var matched = Set<Int>()
        var scrolled = false
        var next = visible.map { observation -> ChatRow in
            if let old = previous[observation.key], counts[observation.key] == old.count {
                let matching = old.count == 1 ? old : old.filter { isNear($0.observation.bounds, observation.bounds) }
                if matching.count == 1, matched.insert(matching[0].id).inserted {
                    var row = matching[0]
                    if abs(row.observation.bounds.midY - observation.bounds.midY) > 8 { scrolled = true }
                    if row.visibleSegments.count == observation.segments.count {
                        row.visibleSegments = zip(row.visibleSegments, observation.segments).map { stabilized($0.0, $0.1) }
                    } else {
                        row.visibleSegments = observation.segments
                    }
                    row.observation = observation
                    row.missedFrames = 0
                    return row
                }
            }
            nextID += 1
            return ChatRow(id: nextID, observation: observation)
        }
        if !scrolled {
            for var old in rows where !matched.contains(old.id) && old.missedFrames == 0 && counts[old.observation.key] == nil {
                let occupied = visible.contains { message in
                    message.segments.contains { current in
                        old.visibleSegments.contains { abs($0.midY - current.midY) <= max(4, current.height / 2) }
                    }
                }
                if !occupied {
                    old.missedFrames = 1
                    next.append(old)
                }
            }
        }
        rows = next.sorted { $0.observation.bounds.midY < $1.observation.bounds.midY }
    }

    mutating func clear() { rows.removeAll() }

    func confirm(_ id: Int, near bounds: CGRect) -> ChatRow? {
        rows.first { $0.id == id && $0.missedFrames == 0 && isNear($0.observation.bounds, bounds) }
    }

    mutating func update(_ id: Int, to state: ChatRow.State) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = state
    }

    func row(_ id: Int) -> ChatRow? { rows.first { $0.id == id } }
}

private func stabilized(_ old: CGRect, _ new: CGRect) -> CGRect {
    let left = abs(old.minX - new.minX) <= 2 ? old.minX : new.minX
    let right = abs(old.maxX - new.maxX) <= 4 ? old.maxX : new.maxX
    let top = abs(old.minY - new.minY) <= 2 ? old.minY : new.minY
    let bottom = abs(old.maxY - new.maxY) <= 2 ? old.maxY : new.maxY
    return CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
}

private func isNear(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= 5 && abs(lhs.midY - rhs.midY) <= 5
}

func cropChat(_ image: CGImage, region: CGRect, windowSize: CGSize) -> CGImage? {
    let scaleX = CGFloat(image.width) / windowSize.width
    let scaleY = CGFloat(image.height) / windowSize.height
    return image.cropping(to: CGRect(x: region.minX * scaleX, y: region.minY * scaleY,
                                     width: region.width * scaleX, height: region.height * scaleY).integral)
}
