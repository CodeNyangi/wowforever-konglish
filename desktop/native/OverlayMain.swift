import AppKit
import OSLog
import ScreenCaptureKit

struct OverlayEvent: Encodable {
    let kind: String
    let text: String
}

struct OverlayCommand: Decodable {
    let action: String
}

@MainActor
final class ChatOverlay: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.wowforever.konglish.overlay", category: "chat")
    private let settings: URL?
    private let demo: Bool
    private var region: ChatRegion?
    private var windowFrame: CGRect?
    private var windowID: CGWindowID?
    private var rows = ChatRows()
    private var panels: [Int: RowPanels] = [:]
    private var selector: OverlayPanel?
    private var visibilityVersion = 0
    private var overlaysVisible = false
    private var status = ""
    private var captureFailures = 0
    private var focusObserver: NSObjectProtocol?
    private var sharedWindow: WindowShare?
    private var demoWindow: NSWindow?
    private var demoView: DemoChat?
    private var notice: OverlayPanel?
    private var noticeUntil: Date?
    private var draftRunning = false
    private let draftInput = DraftInput()
    private var readingChat = false
    private var lastSharedFrame: UInt64?
    private var latestMotion: ChatMotionFrame?
    private var motionReference: (frame: ChatMotionFrame, anchors: [CGRect])?
    private var scrollOffset: CGFloat = 0

    init(settings: URL?, demo: Bool, reselect: Bool) {
        self.settings = settings
        self.demo = demo
        if !reselect, let settings, let data = try? Data(contentsOf: settings) {
            region = try? JSONDecoder().decode(ChatRegion.self, from: data)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard #available(macOS 26.0, *) else {
            emit("error", text: "Mac 오프라인 번역에는 macOS 26 이상이 필요해요.")
            NSApp.terminate(nil)
            return
        }
        Task {
            _ = try? await LocalTranslation.shared.translate("Hello", to: "ko")
            _ = try? await LocalTranslation.shared.translate("안녕하세요", to: "en")
        }
        if demo {
            openDemo()
        } else {
            if !CGPreflightScreenCaptureAccess() {
                let share = WindowShare { [weak self] error in
                    guard let self else { return }
                    if let error {
                        self.emit("error", text: error)
                        NSApp.terminate(nil)
                    } else {
                        self.updateStatus("와우에서 채팅 영역을 지정해 주세요.")
                    }
                }
                sharedWindow = share
                updateStatus("macOS 창 선택에서 World of Warcraft를 선택하세요.")
                share.present()
            }
            focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateForeground()
                }
            }
            if sharedWindow == nil { updateStatus("와우 창으로 돌아가 주세요.") }
            updateForeground()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine() {
                guard let data = line.data(using: .utf8),
                      let command = try? JSONDecoder().decode(OverlayCommand.self, from: data) else { continue }
                Task { @MainActor in self?.receive(command) }
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }

        Task {
            while !Task.isCancelled {
                if demo { tickDemo() }
                else { await tick() }
                try? await Task.sleep(for: .milliseconds(foregroundWoW != nil ? 55 : 240))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        sharedWindow?.close()
    }

    private var foregroundWoW: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.blizzard.worldofwarcraft" else { return nil }
        return app.processIdentifier
    }

    private func updateForeground() {
        let inGame = foregroundWoW != nil
        if !inGame { hidePanels() }
        emit("foreground", text: inGame ? "wow" : "other")
    }

    @available(macOS 14, *)
    private func tick() async {
        guard let pid = foregroundWoW else { hidePanels(); return }
        do {
            if let sharedWindow {
                guard let id = sharedWindow.windowID, let frame = currentFrame(of: id) else { hidePanels(); return }
                guard let region = prepareRegion(frame, id: id) else { return }
                guard let snapshot = sharedWindow.snapshot(), snapshot.number != lastSharedFrame,
                      let crop = snapshot.image(in: region.rect, windowSize: frame.size) else { return }
                lastSharedFrame = snapshot.number
                inspect(crop, region: region.rect, frame: frame, id: id, pid: pid)
                return
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard foregroundWoW == pid else { hidePanels(); return }
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && $0.frame.width >= 400 && $0.frame.height >= 280
            }
            guard let window = windows.first(where: { $0.windowID == windowID }) ??
                windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                hidePanels()
                updateStatus("와우 창을 찾는 중이에요.")
                return
            }

            guard let region = prepareRegion(window.frame, id: window.windowID) else { return }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = max(1, min(2, CGFloat(filter.pointPixelScale)))
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.scalesToFit = true
            config.ignoreShadowsSingleWindow = true
            config.showsCursor = false
            let version = visibilityVersion
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard version == visibilityVersion, foregroundWoW == pid,
                  let crop = cropChat(image, region: region.rect, windowSize: window.frame.size) else { return }
            inspect(crop, region: region.rect, frame: window.frame, id: window.windowID, pid: pid)
        } catch {
            recordCaptureFailure()
        }
    }

    private func recordCaptureFailure() {
        captureFailures += 1
        if captureFailures >= 2 { hidePanels() }
        if captureFailures >= 3 {
            emit("error", text: "와우 화면을 읽지 못했어요. 화면 기록 권한과 창 모드를 확인한 뒤 다시 시작해 주세요.")
            NSApp.terminate(nil)
        }
    }

    private func prepareRegion(_ frame: CGRect, id: CGWindowID) -> ChatRegion? {
        if windowID != id || windowFrame.map({ $0.size != frame.size }) != false {
            resetRows()
            windowID = id
        } else if let windowFrame, !frameMatches(windowFrame, frame) {
            hidePanels()
        }
        windowFrame = frame
        guard let region, region.fits(frame.size) else { showSelector(for: frame); return nil }
        selector?.orderOut(nil)
        return region
    }

    private func inspect(_ crop: CGImage, region: CGRect, frame: CGRect,
                         id: CGWindowID, pid: pid_t) {
        let version = visibilityVersion
        let motion = ChatMotionFrame(image: crop, area: region)
        latestMotion = motion
        if let motion, let reference = motionReference,
           let offset = reference.frame.shift(to: motion, anchors: reference.anchors, in: region),
           abs(offset - scrollOffset) >= 1 {
            let movement = Int((offset - scrollOffset).rounded())
            if abs(movement) >= 8, rows.rows.contains(where: { if case .translated = $0.state { true } else { false } }) {
                logger.notice("Followed translated chat before OCR by \(movement) points")
            }
            scrollOffset = offset
            for panel in panels.values { panel.move(in: frame, region: region, offset: offset) }
        }

        guard !readingChat else { return }
        readingChat = true
        Task {
            defer { readingChat = false }
            do {
                let visible = try await Task.detached(priority: .userInitiated) {
                    try recognizeChat(crop, area: region).filter { !$0.isDraft }
                }.value
                guard visibilityVersion == version, foregroundWoW == pid,
                      let current = currentFrame(of: id), frameMatches(current, frame) else { return }
                captureFailures = 0
                let anchors = visible.flatMap(\.segments)
                motionReference = motion.map { ($0, anchors) }
                scrollOffset = latestMotion.flatMap { newer in
                    motion?.shift(to: newer, anchors: anchors, in: region)
                } ?? 0
                apply(visible, frame: windowFrame ?? frame, region: region)
                updateStatus(rows.rows.isEmpty ? "채팅을 기다리는 중이에요." : "채팅 연결됨")
            } catch {
                if visibilityVersion == version { recordCaptureFailure() }
            }
        }
    }

    private func currentFrame(of id: CGWindowID) -> CGRect? {
        guard let entry = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              entry[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private func frameMatches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1
            && abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }

    private func showSelector(for window: CGRect) {
        updateStatus("와우에서 채팅 영역을 드래그해 주세요.")
        if selector == nil {
            let panel = OverlayPanel()
            let view = RegionSelector()
            view.onSelection = { [weak self] rect in self?.selectRegion(rect) }
            panel.contentView = view
            selector = panel
        }
        selector?.place(screenRect(CGRect(origin: .zero, size: window.size), in: window))
    }

    private func selectRegion(_ rect: CGRect?) {
        selector?.orderOut(nil)
        guard let rect, let windowFrame else {
            NSApp.terminate(nil)
            return
        }
        let selection = ChatRegion(rect: rect, windowSize: windowFrame.size)
        guard selection.fits(windowFrame.size) else { return }
        region = selection
        if let settings {
            do {
                try JSONEncoder().encode(selection).write(to: settings, options: .atomic)
            } catch {
                emit("warning", text: "이번 실행에서만 채팅 영역을 기억해요.")
            }
        }
    }

    private func apply(_ visible: [ChatObservation], frame: CGRect, region: CGRect) {
        let wasVisible = overlaysVisible
        overlaysVisible = true
        let translatedPositions = Dictionary(uniqueKeysWithValues: rows.rows.compactMap { row -> (Int, CGFloat)? in
            guard case .translated = row.state else { return nil }
            return (row.id, row.observation.bounds.midY)
        })
        rows.replace(with: visible)

        let active = Set(rows.rows.map(\.id))
        for id in panels.keys.filter({ !active.contains($0) }) {
            panels.removeValue(forKey: id)?.hide()
        }
        for row in rows.rows {
            if panels[row.id] == nil {
                let id = row.id
                panels[id] = RowPanels { [weak self] line in self?.click(id, line: line) }
            }
            panels[row.id]?.show(row, in: frame, region: region, offset: scrollOffset)
            if let previous = translatedPositions[row.id] {
                if !wasVisible {
                    logger.notice("Restored translated row \(row.id) after returning to WoW")
                } else if abs(row.observation.bounds.midY - previous) > 8 {
                    logger.notice("Translated row \(row.id) moved from \(Int(previous)) to \(Int(row.observation.bounds.midY))")
                }
            }
        }
        if let noticeUntil, noticeUntil <= Date() { notice?.orderOut(nil) }
    }

    private func click(_ id: Int, line: Int) {
        guard (demo || foregroundWoW != nil), let row = rows.row(id), row.missedFrames == 0,
              let windowFrame, let region, #available(macOS 26.0, *) else { return }
        switch row.state {
        case .waiting: return
        case .translated:
            rows.update(id, to: .original)
        case .original, .failed:
            rows.update(id, to: .waiting)
            let start = ContinuousClock.now
            let text = row.observation.body
            let target = row.observation.target
            let lines = row.observation.segments.count
            Task {
                do {
                    let translation = try await LocalTranslation.shared.translate(text, to: target)
                    guard rows.row(id)?.state == .waiting else { return }
                    rows.update(id, to: .translated(translation))
                    logger.notice("Mac translated \(lines) lines to \(target, privacy: .public) in \(start.duration(to: .now).description, privacy: .public); pressed line \(line)")
                } catch {
                    guard rows.row(id)?.state == .waiting else { return }
                    rows.update(id, to: .failed)
                    if overlaysVisible { showNotice(error.localizedDescription) }
                }
                if overlaysVisible, let updated = rows.row(id), let frame = self.windowFrame, let area = self.region {
                    panels[id]?.show(updated, in: frame, region: area.rect, offset: scrollOffset)
                }
            }
        }
        if let updated = rows.row(id) { panels[id]?.show(updated, in: windowFrame, region: region.rect, offset: scrollOffset) }
    }

    private func receive(_ command: OverlayCommand) {
        if command.action == "reselect" {
            resetRows()
            region = nil
            updateStatus("와우에서 채팅 영역을 지정해 주세요.")
        } else if command.action == "draft" {
            logger.notice("Draft shortcut received: game=\(self.foregroundWoW != nil), region=\(self.region != nil), busy=\(self.draftRunning)")
            guard let pid = foregroundWoW, region != nil, !draftRunning,
                  let id = windowID, let frame = currentFrame(of: id) else { return }
            let activity = DraftActivity.current()
            let version = visibilityVersion
            draftRunning = true
            showNotice("영어로 바꾸는 중…")
            Task {
                defer { draftRunning = false }
                await translateDraft(pid: pid, id: id, frame: frame, version: version, activity: activity)
            }
        }
    }

    private func translateDraft(pid: pid_t, id: CGWindowID, frame: CGRect,
                                version: Int, activity: DraftActivity) async {
        guard #available(macOS 26.0, *) else { return }
        let start = ContinuousClock.now
        func isCurrent() -> Bool {
            foregroundWoW == pid && visibilityVersion == version && windowID == id
                && activity == .current()
                && currentFrame(of: id).map { frameMatches($0, frame) } == true
        }
        do {
            guard isCurrent() else {
                logger.notice("Draft cancelled before translation: focus or input changed")
                if foregroundWoW == pid { showNotice("입력 내용이 바뀌었어요 · 다시 ⌘⇧K") }
                return
            }
            guard draftInput.hasPermission() else {
                logger.notice("Draft replacement needs accessibility permission")
                emit("warning", text: "자동 입력하려면 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 Konglish를 허용해 주세요.")
                return
            }
            let source: String
            switch await draftInput.readDraft(in: pid, isCurrent: isCurrent) {
            case .selected(let text): source = text
            case .cancelled:
                logger.notice("Draft cancelled while reading input")
                if foregroundWoW == pid { showNotice("자동 입력 취소됨 · 다시 ⌘⇧K") }
                return
            case .failed:
                logger.notice("Draft selection could not be copied")
                showNotice("입력칸 전체 선택을 확인하지 못했어요 · 다시 ⌘⇧K")
                return
            }
            guard source.range(of: #"\p{Hangul}"#, options: .regularExpression) != nil else {
                showNotice("채팅 입력칸에 한국어를 쓴 뒤 ⌘⇧K를 누르세요.")
                return
            }
            let translation = DraftInput.singleLine(try await LocalTranslation.shared.translate(source, to: "en"))
            guard isCurrent(), !translation.isEmpty else {
                logger.notice("Draft cancelled after translation: focus or input activity changed")
                if foregroundWoW == pid { showNotice("입력 내용이 바뀌었어요 · 다시 ⌘⇧K") }
                return
            }
            let result = await draftInput.replace(in: pid, original: source, translation: translation, isCurrent: isCurrent)
            guard result == .replaced else {
                logger.notice("Draft replacement stopped: selectionFailed=\(result == .selectionFailed)")
                if foregroundWoW == pid {
                    showNotice(result == .selectionFailed ? "전체 선택을 확인하지 못했어요 · 다시 ⌘⇧K" : "자동 입력 취소됨 · 다시 ⌘⇧K")
                }
                return
            }
            showNotice("영어로 바뀜 · Enter로 전송")
            logger.notice("Replaced a WoW draft in \(start.duration(to: .now).description, privacy: .public)")
        } catch {
            if foregroundWoW == pid, visibilityVersion == version { showNotice(error.localizedDescription) }
        }
    }

    private func showNotice(_ message: String) {
        guard let windowFrame, let region else { return }
        let panel = notice ?? OverlayPanel()
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 0.97)
        label.drawsBackground = true
        panel.contentView = label
        panel.ignoresMouseEvents = true
        let box = CGRect(x: region.x, y: max(0, region.y - 42), width: min(region.width, 360), height: 40)
        panel.place(screenRect(box, in: windowFrame))
        notice = panel
        noticeUntil = Date().addingTimeInterval(4)
    }

    private func hidePanels() {
        visibilityVersion += 1
        lastSharedFrame = nil
        motionReference = nil
        latestMotion = nil
        scrollOffset = 0
        selector?.orderOut(nil)
        notice?.orderOut(nil)
        guard overlaysVisible else { return }
        overlaysVisible = false
        for panel in panels.values { panel.hide() }
    }

    private func resetRows() {
        hidePanels()
        panels.removeAll()
        rows.clear()
    }

    private func updateStatus(_ text: String) {
        guard text != status else { return }
        status = text
        emit("status", text: text)
    }

    private func emit(_ kind: String, text: String) {
        guard var bytes = try? JSONEncoder().encode(OverlayEvent(kind: kind, text: text)) else { return }
        bytes.append(10)
        FileHandle.standardOutput.write(bytes)
    }

    private func openDemo() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 650, height: 355),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Konglish Overlay Demo"
        window.isReleasedWhenClosed = false
        let view = DemoChat()
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        demoWindow = window
        demoView = view
    }

    private func tickDemo() {
        guard let window = demoWindow, let view = demoView, window.isVisible else {
            NSApp.terminate(nil)
            return
        }
        let box = window.convertToScreen(view.convert(view.bounds, to: nil))
        let frame = CGRect(x: box.minX, y: desktopTop - box.maxY, width: box.width, height: box.height)
        if windowFrame != frame { resetRows(); windowFrame = frame }
        let area = CGRect(x: 20, y: 155, width: 580, height: 135)
        region = ChatRegion(rect: area, windowSize: box.size)
        apply(view.observations(), frame: frame, region: area)
    }
}

@MainActor
final class DemoChat: NSView {
    private let phrases = ["Mana break after this pull?", "Please kick the next cast.", "Give me a second to get mana."]
    private var scrolled = false
    private let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
    private let prefix = "[Party] [Tank]: "
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let scroll = NSButton(title: "채팅 스크롤 테스트", target: self, action: #selector(toggleScroll))
        scroll.frame = CGRect(x: 24, y: 80, width: 160, height: 28)
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func toggleScroll() { scrolled.toggle(); needsDisplay = true }

    private var lines: [(String, CGFloat)] {
        scrolled ? [(phrases[1], 180), (phrases[2], 204)] : [(phrases[0], 180), (phrases[1], 204)]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        bounds.fill()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21, weight: .bold), .foregroundColor: NSColor.white]
        ("와우 채팅 오버레이 테스트" as NSString).draw(at: CGPoint(x: 24, y: 23), withAttributes: heading)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedRed: 0.67, green: 0.72, blue: 1, alpha: 1)]
        for (line, y) in lines {
            ((prefix + line) as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: attributes)
        }
    }

    func observations() -> [ChatObservation] {
        let x = 24 + (prefix as NSString).size(withAttributes: [.font: font]).width
        return lines.map { text, y in
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            return ChatObservation(line: prefix + text, body: text, bounds: CGRect(x: x, y: y + 1, width: width, height: 16))
        }
    }
}

@main
struct OverlayMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        let isDemo = arguments.contains("--demo")
        let settings = arguments.dropFirst().first(where: { !$0.hasPrefix("--") })
            .map { URL(fileURLWithPath: $0) }
        let app = NSApplication.shared
        app.setActivationPolicy(isDemo ? .regular : .accessory)
        let controller = ChatOverlay(settings: settings, demo: isDemo, reselect: arguments.contains("--reselect"))
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
