import AppKit

func questionBubbleSize(text: String, title: String, expanded: Bool, screen: CGSize) -> CGSize {
    let available = CGSize(width: max(1, screen.width - 12), height: max(1, screen.height - 12))
    if !expanded {
        let font = NSFont.systemFont(ofSize: 13)
        let lineWidth = title.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(available.width, 340, max(160, ceil(lineWidth) + 26))
        let measured = (title as NSString).boundingRect(with: CGSize(width: max(1, width - 26), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return CGSize(width: width, height: min(available.height, max(30, ceil(measured.height) + 14)))
    }
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let lineWidth = text.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
    let width = min(available.width, 480, max(230, ceil(lineWidth) + 24, min(320, ceil(titleWidth) + 20)))
    let measured = (text as NSString).boundingRect(with: CGSize(width: max(1, width - 24), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    return CGSize(width: width, height: min(available.height, max(97, ceil(measured.height) + 84)))
}

func compactBubbleTitle(agent: Agent, content: String?) -> String {
    let label = agent.label ?? ""
    let issue = label.range(of: "\\b[A-Z][A-Z0-9]+-[0-9]+\\b", options: .regularExpression).map { String(label[$0]) }
    let role = label.range(of: "\\b(?:Orchestrator|Implementer|Reviewer|Researcher|Explorer|Oracle|QA)(?:[[:space:]]+[0-9]+)?\\b", options: [.regularExpression, .caseInsensitive]).map {
        let words = label[$0].split(whereSeparator: \.isWhitespace)
        return (words[0].lowercased() == "qa" ? "QA" : words[0].capitalized) + (words.count > 1 ? " " + words[1] : "")
    }
    let identity = [issue, role].compactMap { $0 }.joined(separator: " · ")
    let preview = attentionQuestionPreview(content ?? "Waiting for input. Open the agent.")
    return identity.isEmpty ? preview : identity + "\n" + preview
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
    private var needsContentLayout = true
    private var compactTitleCache: (label: String?, content: String?, title: String)?
    private var sizeCache: (body: String, title: String, expanded: Bool, screen: CGSize, size: CGSize)?

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
        compact.cell?.wraps = true; compact.cell?.usesSingleLineMode = false
        compact.cell?.lineBreakMode = .byWordWrapping
        compact.font = .systemFont(ofSize: 13)
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

    func update(agent: Agent, content: String?, expanded: Bool, error: String?) {
        if self.expanded != expanded { needsContentLayout = true }
        self.expanded = expanded
        let name = "\(agent.machine) · \(agent.label ?? agent.agent ?? "Agent")"
        let preview: String
        if let cached = compactTitleCache, cached.label == agent.label, cached.content == content {
            preview = cached.title
        } else {
            preview = compactBubbleTitle(agent: agent, content: content)
            compactTitleCache = (agent.label, content, preview)
        }
        if compact.title != preview { compact.title = preview }
        let tip = "Click to read the current question and choices."
        if compact.toolTip != tip { compact.toolTip = tip }
        let title = error ?? ((demo ? "Preview · " : content == nil ? "Waiting for input · " : "Latest terminal text · ") + name)
        if header.stringValue != title { header.stringValue = title }
        if text.string != content ?? "Waiting for input. Open the agent to view its question." {
            text.string = content ?? "Waiting for input. Open the agent to view its question."
            needsContentLayout = true
        }
        let enabled = agent.sessionKey != nil && agent.pane_id != nil
        if open.isEnabled != enabled { open.isEnabled = enabled }
        let openTitle = agent.machine == "local" ? "Open agent" : "Open remote"
        if open.title != openTitle { open.title = openTitle }
        let openTip = agent.machine == "local" ? "Open this agent in Herdr." : "Open this remote agent in a new Ghostty window."
        if open.toolTip != openTip { open.toolTip = openTip }
        if compact.isHidden != expanded { compact.isHidden = expanded }
        for child in [header, scroll, open, collapse] where child.isHidden == expanded { child.isHidden = !expanded }
        let accessibleTitle = expanded ? title : preview
        if panel.contentView?.accessibilityLabel() != accessibleTitle { panel.contentView?.setAccessibilityLabel(accessibleTitle) }
    }

    func preferredSize(body: String, title: String, screen: CGSize) -> CGSize {
        if let saved = sizeCache, saved.body == body, saved.title == title, saved.expanded == expanded, saved.screen == screen { return saved.size }
        let size = questionBubbleSize(text: body, title: title, expanded: expanded, screen: screen)
        sizeCache = (body, title, expanded, screen, size)
        return size
    }

    func layout(in rect: CGRect) {
        let resized = panel.frame.size != rect.size
        if panel.frame != rect {
            if resized { panel.setFrame(rect, display: false) } else { panel.setFrameOrigin(rect.origin) }
        }
        guard resized || needsContentLayout else { return }
        needsContentLayout = false
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
        let blocked = agents.filter { $0.needsAttention && !$0.asleep && pets[$0.id] != nil }.sorted { $0.id < $1.id }
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
            bubble.update(agent: agent, content: texts[id], expanded: id == selected, error: id == selected ? focusError : nil)
            let head = CGPoint(x: origin.x + pet.badge.position.x, y: origin.y + pet.badge.position.y)
            let body = texts[id] ?? "Waiting for input. Open the agent to view its question."
            let title = id == selected ? bubble.header.stringValue : bubble.compact.title
            let size = bubble.preferredSize(body: body, title: title, screen: screen.size)
            let rect = bubbleRect(above: head, size: size, screen: screen, occupied: occupied)
            occupied.append(rect)
            bubble.layout(in: rect)
            if !bubble.panel.isVisible { bubble.panel.orderFrontRegardless() }
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
            self?.focusError = success ? nil : "Cannot open this agent. Check its machine connection or open it in Herdr."
            scene.wake()
        }
    }
}
