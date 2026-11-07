import AppKit
import CoreText

var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

func screenRect(_ rect: CGRect, in window: CGRect) -> CGRect {
    CGRect(x: window.minX + rect.minX, y: desktopTop - window.minY - rect.maxY,
           width: rect.width, height: rect.height)
}

@MainActor
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for item in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(item)?.isHidden = true
        }
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        if #available(macOS 26, *) {
            collectionBehavior = [.canJoinAllApplications, .stationary, .ignoresCycle]
        } else {
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(_ bounds: CGRect) {
        let target = bounds.integral
        if frame.size != target.size { setFrame(target, display: true) }
        else if frame.origin != target.origin { setFrameOrigin(target.origin) }
        if !isVisible { orderFrontRegardless() }
    }
}

@MainActor
final class RegionSelector: NSView {
    var onSelection: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor(calibratedRed: 0.30, green: 0.91, blue: 0.65, alpha: 0.23).setFill()
            selection.fill()
            NSColor.systemMint.setStroke()
            NSBezierPath(rect: selection).stroke()
        }
        let hint = "채팅창 전체를 드래그하세요 · 입력 중 번역도 쓰려면 입력칸 포함 · 우클릭으로 취소"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        ]
        (hint as NSString).draw(at: CGPoint(x: 24, y: 24), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        if selection.width >= 100 && selection.height >= 24 { onSelection?(selection) }
    }

    override func rightMouseDown(with event: NSEvent) { onSelection?(nil) }
}

@MainActor
final class RowButton: NSButton {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc func clicked() { onClick?() }
}

@MainActor
final class RowPanels {
    private let onClick: (Int) -> Void
    private var lines: [(OverlayPanel, RowButton)] = []
    private var positions: [CGRect] = []

    init(click: @escaping (Int) -> Void) {
        onClick = click
    }

    private func addLine() {
        let panel = OverlayPanel()
        let line = RowButton()
        line.isBordered = false
        line.alignment = .left
        line.cell?.lineBreakMode = .byTruncatingTail
        line.wantsLayer = true
        line.target = line
        line.action = #selector(RowButton.clicked)
        let index = lines.count + 1
        let click = onClick
        line.onClick = { click(index) }
        panel.contentView = line
        lines.append((panel, line))
    }

    func hide() {
        for (panel, _) in lines { panel.orderOut(nil) }
    }

    func show(_ row: ChatRow, in window: CGRect, region: CGRect, offset: CGFloat) {
        guard !row.visibleSegments.isEmpty else { hide(); return }
        while lines.count < row.visibleSegments.count { addLine() }
        positions.removeAll(keepingCapacity: true)

        if case .translated(let translation) = row.state {
            showTranslation(translation, segments: row.visibleSegments, right: region.maxX)
        } else {
            for (index, segment) in row.visibleSegments.enumerated() {
                let height = min(21, segment.height + 4)
                let hitArea = CGRect(x: segment.minX, y: segment.midY - height / 2,
                                     width: segment.width, height: height)
                configureLine(index, at: hitArea, count: row.visibleSegments.count,
                          waiting: row.state == .waiting)
            }
        }
        move(in: window, region: region, offset: offset)
    }

    func move(in window: CGRect, region: CGRect, offset: CGFloat) {
        for (index, pair) in lines.enumerated() {
            let (panel, _) = pair
            if index < positions.count {
                let bounds = positions[index].offsetBy(dx: 0, dy: offset)
                if bounds.midY >= region.minY, bounds.midY <= region.maxY {
                    panel.place(screenRect(bounds, in: window))
                    continue
                }
            }
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    private func configureLine(_ index: Int, at bounds: CGRect, count: Int,
                               translation: String? = nil, font: NSFont? = nil, waiting: Bool = false) {
        let (_, line) = lines[index]
        let background = translation == nil ? NSColor(white: 1, alpha: 0.012) : NSColor(white: 0.065, alpha: 1)
        if line.layer?.backgroundColor != background.cgColor { line.layer?.backgroundColor = background.cgColor }
        let title = NSAttributedString(string: translation ?? "", attributes: [
            .foregroundColor: NSColor(calibratedRed: 0.78, green: 1, blue: 0.89, alpha: 1),
            .font: font ?? NSFont.systemFont(ofSize: 12),
        ])
        if line.attributedTitle != title { line.attributedTitle = title }
        let label = translation ?? (waiting ? "번역 중" : "이 메시지 번역, \(count)줄 중 \(index + 1)번째 줄")
        if line.accessibilityLabel() != label { line.setAccessibilityLabel(label) }
        positions.append(bounds)
    }

    private func showTranslation(_ translation: String, segments: [CGRect], right: CGFloat) {
        let message = translation.split(whereSeparator: \.isNewline).joined(separator: " ") as NSString
        let font = NSFont.systemFont(ofSize: min(15, max(9, segments[0].height)))
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: message as String, attributes: [.font: font]))
        var offset = 0
        for (index, segment) in segments.enumerated() {
            let isLast = index == segments.count - 1
            let available = max(segment.width, right - segment.minX)
            let remaining = message.length - offset
            let length = isLast || remaining == 0 ? remaining :
                min(remaining, CTTypesetterSuggestLineBreak(typesetter, offset, Double(max(1, available - 4))))
            let part = message.substring(with: NSRange(location: offset, length: length))
                .trimmingCharacters(in: .whitespaces)
            offset += length
            let partWidth = (part as NSString).size(withAttributes: [.font: font]).width + 4
            let width = min(available, max(segment.width + 1, partWidth))
            let height = min(22, max(12, segment.height + 3))
            let bounds = CGRect(x: segment.minX, y: segment.midY - height / 2, width: width, height: height)
            configureLine(index, at: bounds, count: segments.count, translation: part, font: font)
        }
    }
}
