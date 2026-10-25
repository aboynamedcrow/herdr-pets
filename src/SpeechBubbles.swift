import AppKit

func questionBubbleSize(text: String, title: String, expanded: Bool, screen: CGSize) -> CGSize {
    let available = CGSize(width: max(1, screen.width - 12), height: max(1, screen.height - 12))
    if !expanded {
        let width = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 26
        return CGSize(width: min(available.width, ceil(width)), height: min(available.height, 30))
    }
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let lineWidth = text.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
    let width = min(available.width, 480, max(230, ceil(lineWidth) + 24, min(320, ceil(titleWidth) + 20)))
    let measured = (text as NSString).boundingRect(with: CGSize(width: max(1, width - 28), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    return CGSize(width: width, height: min(available.height, max(97, ceil(measured.height) + 84)))
}

func bubbleRect(above head: CGPoint, size: CGSize, screen: CGRect, occupied: [CGRect]) -> CGRect {
    let area = screen.insetBy(dx: 6, dy: 6)
    let size = CGSize(width: min(size.width, max(1, area.width)), height: min(size.height, max(1, area.height)))
    func rect(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: min(max(x, area.minX), area.maxX - size.width), y: min(max(y, area.minY), area.maxY - size.height), width: size.width, height: size.height)
    }
    let first = rect(head.x - size.width / 2, head.y + 8)
    var best = first, least = CGFloat.greatestFiniteMagnitude
    var candidates = [first,
        rect(head.x + 12, head.y + 8), rect(head.x - size.width - 12, head.y + 8),
        rect(head.x - size.width / 2, head.y - size.height - 8),
        rect(head.x + 12, head.y - size.height - 8), rect(head.x - size.width - 12, head.y - size.height - 8)]
    for row in 0..<12 { for column in 0..<8 {
        candidates.append(rect(area.minX + CGFloat(column) * (size.width + 8), area.maxY - size.height - CGFloat(row) * (size.height + 8)))
    } }
    for candidate in candidates {
        let overlap = occupied.reduce(CGFloat.zero) { sum, other in
            let intersection = candidate.insetBy(dx: -4, dy: -4).intersection(other)
            return sum + (intersection.isNull ? 0 : intersection.width * intersection.height)
        }
        if overlap < least { best = candidate; least = overlap }
        if overlap == 0 { break }
    }
    return best
}

private final class BubbleButton: NSButton {
    var invoke: (() -> Void)?
    convenience init(_ title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.invoke = action; target = self; self.action = #selector(run)
        bezelStyle = .rounded
    }
    @objc private func run() { invoke?() }
}

private final class SpeechBubble {
    let panel: NSPanel
    let header = NSTextField(labelWithString: "")
    let text = NSTextView()
    let compact: BubbleButton
    let open: BubbleButton
    let collapse: BubbleButton
    let scroll = NSScrollView()
    var expanded = false

    init(select: @escaping () -> Void, focus: @escaping () -> Void, minimize: @escaping () -> Void) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        let background = NSVisualEffectView()
        background.material = .popover; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 10
        panel.contentView = background
        compact = BubbleButton("Waiting for input", action: select)
        open = BubbleButton("Open agent", action: focus)
        collapse = BubbleButton("Collapse", action: minimize)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.lineBreakMode = .byTruncatingTail
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textColor = .labelColor; text.textContainerInset = CGSize(width: 4, height: 4)
        text.textContainer?.lineFragmentPadding = 0
        text.isRichText = false; text.importsGraphics = false
        text.isContinuousSpellCheckingEnabled = false; text.isGrammarCheckingEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticLinkDetectionEnabled = false; text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; scroll.documentView = text
        for child in [compact, header, scroll, open, collapse] { background.addSubview(child) }
    }

    func update(agent: Agent, content: String?, expanded: Bool) {
        self.expanded = expanded
        let name = "\(agent.machine) · \(agent.label ?? agent.agent ?? "Agent")"
        compact.title = "! " + name
        compact.toolTip = content == nil ? "Waiting for input. Click to open the question." : "Click to read the terminal excerpt."
        header.stringValue = (demo ? "Preview · " : content == nil ? "Waiting for input · " : "Terminal excerpt · ") + name
        if text.string != content ?? "Waiting for input. Open the agent to view its question." {
            text.string = content ?? "Waiting for input. Open the agent to view its question."
        }
        open.isEnabled = agent.sessionKey != nil && agent.pane_id != nil
        compact.isHidden = expanded
        for child in [header, scroll, open, collapse] { child.isHidden = !expanded }
        panel.contentView?.setAccessibilityLabel(header.stringValue)
    }

    func layout(in rect: CGRect) {
        panel.setFrame(rect, display: true)
        let width = rect.width, height = rect.height
        compact.frame = CGRect(x: 0, y: 0, width: width, height: height)
        header.frame = CGRect(x: 10, y: height - 26, width: width - 20, height: 18)
        scroll.frame = CGRect(x: 8, y: 42, width: max(1, width - 16), height: max(1, height - 76))
        text.setFrameSize(CGSize(width: max(1, scroll.contentSize.width), height: max(text.frame.height, scroll.contentSize.height)))
        text.textContainer?.containerSize = CGSize(width: max(1, scroll.contentSize.width), height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.sizeToFit()
        open.frame = CGRect(x: 10, y: 7, width: 110, height: 28)
        collapse.frame = CGRect(x: max(125, width - 100), y: 7, width: 90, height: 28)
    }
}

final class SpeechBubbles {
    private var bubbles: [String: SpeechBubble] = [:]
    private var selected: String?
    private var agents: [String: Agent] = [:]
    private var focusError: String?

    func hideAll() {
        bubbles.values.forEach { $0.panel.orderOut(nil) }
        bubbles.removeAll(); agents.removeAll(); selected = nil; focusError = nil
    }

    func update(agents: [Agent], pets: [String: Pet], texts: [String: String], origin: CGPoint, screen: CGRect) {
        let blocked = agents.filter { $0.agent_status == "blocked" && !$0.asleep && pets[$0.id] != nil }.sorted { $0.id < $1.id }
        let ids = Set(blocked.map(\.id))
        for (id, bubble) in bubbles where !ids.contains(id) { bubble.panel.orderOut(nil); bubbles[id] = nil }
        self.agents = Dictionary(uniqueKeysWithValues: blocked.map { ($0.id, $0) })
        if selected == nil || (selected != "" && !ids.contains(selected!)) { selected = blocked.first?.id }
        var occupied: [CGRect] = []
        let ordered = blocked.sorted { ($0.id == selected ? 0 : 1, $0.id) < ($1.id == selected ? 0 : 1, $1.id) }
        for agent in ordered {
            let id = agent.id, pet = pets[id]!
            let bubble = bubbles[id] ?? SpeechBubble(select: { [weak self] in self?.selected = id; self?.focusError = nil; scene.wake() }, focus: { [weak self] in self?.focus(id) }, minimize: { [weak self] in self?.selected = ""; scene.wake() })
            bubbles[id] = bubble
            bubble.update(agent: agent, content: texts[id], expanded: id == selected)
            if id == selected, let focusError { bubble.header.stringValue = focusError }
            let head = CGPoint(x: origin.x + pet.badge.position.x, y: origin.y + pet.badge.position.y)
            let body = texts[id] ?? "Waiting for input. Open the agent to view its question."
            let title = id == selected ? bubble.header.stringValue : bubble.compact.title
            let size = questionBubbleSize(text: body, title: title, expanded: id == selected, screen: screen.size)
            let rect = bubbleRect(above: head, size: size, screen: screen, occupied: occupied)
            occupied.append(rect)
            bubble.layout(in: rect)
            bubble.panel.orderFrontRegardless()
        }
    }

    func exportPreviews(to directory: URL) throws {
        for (index, entry) in bubbles.sorted(by: { $0.key < $1.key }).enumerated() {
            let bubble = entry.value
            guard let view = bubble.panel.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                bubble.panel.displayIfNeeded()
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("bubble-\(index).png"))
        }
    }

    private func focus(_ id: String) {
        guard let agent = agents[id] else { return }
        focusPetAgent(agent) { [weak self] success in
            guard self?.agents[id]?.sessionKey == agent.sessionKey else { return }
            self?.focusError = success ? nil : "Cannot open this agent. Its session or machine changed."
            scene.wake()
        }
    }
}
