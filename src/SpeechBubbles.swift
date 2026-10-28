import AppKit

let questionPreviewLineCount = 1
private let bubbleBlue = NSColor(srgbRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)

func questionBubbleSize(text: String, title: String, expanded: Bool, screen: CGSize) -> CGSize {
    let available = CGSize(width: max(1, screen.width - 12), height: max(1, screen.height - 12))
    let font = NSFont.systemFont(ofSize: 13)
    let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    let textFieldInsets: CGFloat = 4
    let titleWidth = ceil((title as NSString).size(withAttributes: [.font: headerFont]).width) + textFieldInsets
    if !expanded {
        let previewWidth = ceil((attentionQuestionPreview(text) as NSString).size(withAttributes: [.font: font]).width) + textFieldInsets
        let width = min(available.width, 340, max(100, max(titleWidth, previewWidth) + 28))
        let height: CGFloat = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 32 : 36 + CGFloat(questionPreviewLineCount) * 18
        return CGSize(width: width, height: min(available.height, height))
    }
    let body = joinedQuestionLines(text)
    let lineWidth = body.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    let width = min(available.width, 480, max(230, ceil(lineWidth) + 28, min(340, titleWidth + 28)))
    let measured = (body as NSString).boundingRect(with: CGSize(width: max(1, width - 28), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    return CGSize(width: width, height: min(available.height, max(98, ceil(measured.height) + 82)))
}

func compactBubbleTitle(agent: Agent, machineName: String? = nil) -> String {
    let label = (agent.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let issue = label.range(of: "\\b[A-Z][A-Z0-9]+-[0-9]+\\b", options: .regularExpression).map { String(label[$0]) }
    let role = label.range(of: "\\b(?:Orchestrator|Implementer|Reviewer|Researcher|Explorer|Oracle|QA)(?:[[:space:]]+[0-9]+)?\\b", options: [.regularExpression, .caseInsensitive]).map {
        let words = label[$0].split(whereSeparator: \.isWhitespace)
        return (words[0].lowercased() == "qa" ? "QA" : words[0].capitalized) + (words.count > 1 ? " " + words[1] : "")
    }
    let identity = [issue, role].compactMap { $0 }.joined(separator: " · ")
    let name = identity.isEmpty ? (label.isEmpty ? agent.agent ?? "Agent" : label) : identity
    let machine = machineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return agent.machine != "local" && !machine.isEmpty ? name + " · " + machine : name
}

// The collapsed size is the minimum. A prior expanded frame supplies position only.
func expandedBubbleRect(from anchor: CGRect, size: CGSize, screen: CGRect,
                        previous: CGRect? = nil, pointer: CGPoint? = nil) -> CGRect {
    let area = screen.insetBy(dx: 6, dy: 6)
    let size = CGSize(width: min(max(size.width, anchor.width), max(1, area.width)),
                      height: min(max(size.height, anchor.height), max(1, area.height)))
    let placement = previous ?? anchor
    var x = placement.minX, y = placement.maxY - size.height
    if let pointer {
        x = min(x, pointer.x - 1)
        x = max(x, pointer.x - size.width + 1)
        y = min(y, pointer.y - 1)
        y = max(y, pointer.y - size.height + 1)
    }
    return CGRect(x: min(max(x, area.minX), area.maxX - size.width),
                  y: min(max(y, area.minY), area.maxY - size.height),
                  width: size.width, height: size.height)
}

enum BubbleClickTarget { case none, openAgent, textSelection, control }

func bubbleClickTarget(inside: Bool, expanded: Bool, overText: Bool, overControl: Bool) -> BubbleClickTarget {
    guard inside else { return .none }
    guard expanded else { return .openAgent }
    if overControl { return .control }
    return overText ? .textSelection : .openAgent
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
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
        font = .systemFont(ofSize: 12, weight: .semibold)
        contentTintColor = bubbleBlue
    }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func run() { invoke?() }
}

private final class BubbleSurface: NSView {
    var hover: ((Bool) -> Void)?
    var click: (() -> Void)?
    var expanded = false
    weak var body: NSTextView?
    weak var openControl: NSButton?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { click?() }

    private func isOverText(_ point: CGPoint) -> Bool {
        guard let body, let container = body.textContainer, let layout = body.layoutManager else { return false }
        let local = body.convert(point, from: self)
        let origin = body.textContainerOrigin
        let location = CGPoint(x: local.x - origin.x, y: local.y - origin.y)
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndex(for: location, in: container)
        guard glyph < layout.numberOfGlyphs else { return false }
        return layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(location)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let hit = super.hitTest(point)
        let overControl = hit is NSScroller || (openControl.map { hit === $0 || hit?.isDescendant(of: $0) == true } ?? false)
        let overText = expanded && hit === body && isOverText(local)
        switch bubbleClickTarget(inside: bounds.contains(local), expanded: expanded, overText: overText, overControl: overControl) {
        case .none: return nil
        case .openAgent: return self
        case .textSelection, .control: return hit
        }
    }
}

private final class BubblePanel: NSPanel {
    // Keep standard text selection and Copy available. Only the text view requests key focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SpeechBubble {
    let panel: NSPanel
    let surface = BubbleSurface()
    let header = NSTextField(labelWithString: "")
    let preview = NSTextField(labelWithString: "")
    let text = NSTextView()
    let open: BubbleButton
    let scroll = NSScrollView()
    var expanded = false
    var anchor: CGRect?
    var expandedFrame: CGRect?
    var canExpand = false
    private var needsContentLayout = true
    private var contentCache: String?
    private var identityCache: (label: String?, agent: String?, machine: String, machineName: String?, title: String)?
    private var sizeCache: (body: String, title: String, expanded: Bool, screen: CGSize, size: CGSize)?

    init(focus: @escaping () -> Void, hover: @escaping (Bool) -> Void) {
        panel = BubblePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        surface.wantsLayer = true
        surface.layer?.backgroundColor = bubbleBlue.cgColor
        surface.layer?.cornerRadius = 17
        surface.hover = hover; surface.click = focus
        panel.contentView = surface
        open = BubbleButton("Open agent", action: focus)
        surface.body = text; surface.openControl = open
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .white
        header.lineBreakMode = .byTruncatingTail
        header.maximumNumberOfLines = 1
        preview.font = .systemFont(ofSize: 13)
        preview.textColor = .white
        preview.maximumNumberOfLines = questionPreviewLineCount
        preview.lineBreakMode = .byTruncatingTail
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .white; text.textContainerInset = CGSize(width: 0, height: 0)
        text.selectedTextAttributes = [.backgroundColor: NSColor.white, .foregroundColor: bubbleBlue]
        text.textContainer?.lineFragmentPadding = 0
        text.isRichText = false; text.importsGraphics = false
        text.isContinuousSpellCheckingEnabled = false; text.isGrammarCheckingEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticLinkDetectionEnabled = false; text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.documentView = text
        for child in [header, preview, scroll, open] { surface.addSubview(child) }
    }

    func update(agent: Agent, content: String?, machineName: String?, expanded: Bool, error: String?) {
        let body = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        canExpand = !body.isEmpty
        let expanded = expanded && canExpand
        if self.expanded != expanded { needsContentLayout = true }
        self.expanded = expanded
        surface.expanded = expanded
        let identity: String
        if let cached = identityCache, cached.label == agent.label, cached.agent == agent.agent,
           cached.machine == agent.machine, cached.machineName == machineName {
            identity = cached.title
        } else {
            identity = compactBubbleTitle(agent: agent, machineName: machineName)
            identityCache = (agent.label, agent.agent, agent.machine, machineName, identity)
        }
        let title = error ?? identity
        if header.stringValue != title { header.stringValue = title }
        if contentCache != body {
            contentCache = body
            preview.stringValue = attentionQuestionPreview(body)
            text.string = joinedQuestionLines(body)
            needsContentLayout = true
        }
        let enabled = agent.sessionKey != nil && agent.pane_id != nil
        if open.isEnabled != enabled { open.isEnabled = enabled }
        let openTitle = agent.machine == "local" ? "Open agent" : "Open remote"
        if open.title != openTitle { open.title = openTitle }
        let tip = agent.machine == "local" ? "Open this agent in Herdr." : "Open this remote agent in a new Ghostty window."
        if open.toolTip != tip { open.toolTip = tip }
        preview.isHidden = expanded || !canExpand
        scroll.isHidden = !expanded; open.isHidden = !expanded
        let accessible = expanded || preview.stringValue.isEmpty ? title : title + "\n" + preview.stringValue
        if surface.accessibilityLabel() != accessible { surface.setAccessibilityLabel(accessible) }
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
        header.frame = CGRect(x: 14, y: height - 25, width: max(1, width - 28), height: 16)
        preview.frame = CGRect(x: 14, y: 9, width: max(1, width - 28), height: CGFloat(questionPreviewLineCount) * 18)
        scroll.frame = CGRect(x: 14, y: 44, width: max(1, width - 28), height: max(1, height - 82))
        text.setFrameSize(CGSize(width: max(1, scroll.contentSize.width), height: max(text.frame.height, scroll.contentSize.height)))
        text.textContainer?.containerSize = CGSize(width: max(1, scroll.contentSize.width), height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.sizeToFit()
        open.frame = CGRect(x: 14, y: 10, width: min(110, max(1, width - 28)), height: 26)
    }
}

final class SpeechBubbles {
    private var bubbles: [String: SpeechBubble] = [:]
    private var selected: String?
    private var agents: [String: Agent] = [:]
    private var focusError: (id: String, message: String)?
    private var collapseTask: DispatchWorkItem?
    private var refresh: (() -> Void)?

    func hideAll() {
        collapseTask?.cancel(); collapseTask = nil
        bubbles.values.forEach { $0.panel.orderOut(nil) }
        bubbles.removeAll(); agents.removeAll(); selected = nil; focusError = nil; refresh = nil
    }

    func update(agents: [Agent], pets: [String: Pet], texts: [String: String], origin: CGPoint, screen: CGRect,
                machineNames: [String: String] = [:], expandPreview: Bool = false) {
        refresh = { [weak self] in
            self?.update(agents: agents, pets: pets, texts: texts, origin: origin, screen: screen, machineNames: machineNames, expandPreview: expandPreview)
        }
        let blocked = agents.filter { $0.needsAttention && !$0.asleep && pets[$0.id] != nil }.sorted { $0.id < $1.id }
        let ids = Set(blocked.map(\.id))
        for (id, bubble) in bubbles where !ids.contains(id) { bubble.panel.orderOut(nil); bubbles[id] = nil }
        self.agents = Dictionary(uniqueKeysWithValues: blocked.map { ($0.id, $0) })
        if let selected, !ids.contains(selected) || (texts[selected] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.selected = nil
            collapseTask?.cancel(); collapseTask = nil
        }
        let previewID = expandPreview ? (blocked.first { $0.machine != "local" } ?? blocked.first)?.id : nil
        let expandedID = selected ?? previewID
        var occupied: [CGRect] = []
        let ordered = blocked.sorted { ($0.id == expandedID ? 0 : 1, $0.id) < ($1.id == expandedID ? 0 : 1, $1.id) }
        for agent in ordered {
            let id = agent.id, pet = pets[id]!
            let bubble = bubbles[id] ?? SpeechBubble(focus: { [weak self] in self?.focus(id) }, hover: { [weak self] inside in self?.hover(id, inside: inside) })
            bubbles[id] = bubble
            bubble.update(agent: agent, content: texts[id], machineName: machineNames[agent.machine], expanded: id == expandedID,
                          error: focusError?.id == id ? focusError?.message : nil)
            let head = CGPoint(x: origin.x + pet.badge.position.x, y: origin.y + pet.badge.position.y)
            let size = bubble.preferredSize(body: texts[id] ?? "", title: bubble.header.stringValue, screen: screen.size)
            let rect: CGRect
            if bubble.expanded, let anchor = bubble.anchor {
                let pointer = bubble.panel.frame.contains(NSEvent.mouseLocation) ? NSEvent.mouseLocation : nil
                rect = expandedBubbleRect(from: anchor, size: size, screen: screen, previous: bubble.expandedFrame, pointer: pointer)
                bubble.expandedFrame = rect
            } else if !bubble.expanded, let anchor = bubble.anchor {
                let placement = bubble.expandedFrame ?? anchor
                let collapsed = CGRect(x: placement.minX, y: placement.maxY - size.height, width: size.width, height: size.height)
                rect = expandedBubbleRect(from: collapsed, size: size, screen: screen)
                bubble.anchor = nil; bubble.expandedFrame = nil
            } else { rect = bubbleRect(above: head, size: size, screen: screen, occupied: occupied) }
            occupied.append(rect)
            bubble.layout(in: rect)
            if !bubble.panel.isVisible { bubble.panel.orderFrontRegardless() }
        }
    }

    private func hover(_ id: String, inside: Bool) {
        guard let bubble = bubbles[id], bubble.canExpand else { return }
        if inside {
            collapseTask?.cancel(); collapseTask = nil
            guard selected != id else { return }
            bubble.anchor = bubble.panel.frame
            selected = id; focusError = nil
            refresh?()
            bubble.panel.orderFrontRegardless()
        } else if selected == id {
            collapseTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.selected == id, let bubble = self.bubbles[id] else { return }
                guard !bubble.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.selected = nil; self.collapseTask = nil
                self.refresh?()
            }
            collapseTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
    }

    func exportPreviews(to directory: URL) throws {
        for (index, entry) in bubbles.sorted(by: { $0.key < $1.key }).enumerated() {
            let bubble = entry.value
            guard let view = bubble.panel.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            view.effectiveAppearance.performAsCurrentDrawingAppearance { bubble.panel.displayIfNeeded() }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("bubble-\(index).png"))
        }
    }

    private func focus(_ id: String) {
        guard let agent = agents[id] else { return }
        focusPetAgent(agent) { [weak self] success in
            guard self?.agents[id]?.sessionKey == agent.sessionKey else { return }
            self?.focusError = success ? nil : (id, "Cannot open this agent. Check its machine connection or open it in Herdr.")
            self?.refresh?()
        }
    }
}
