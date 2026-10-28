import AppKit

let questionPreviewLineCount = 1
private enum BubbleMetrics {
    static let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let buttonFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let cornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 10
    static let headerHeight: CGFloat = 18
    static let previewHeight = CGFloat(questionPreviewLineCount) * 18
    static let headerGap: CGFloat = 4
    static let buttonGap: CGFloat = 8
    static let buttonWidth: CGFloat = 110
    static let buttonHeight: CGFloat = {
        let button = NSButton(title: "Open remote", target: nil, action: nil)
        button.font = buttonFont
        button.bezelStyle = .rounded
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { button.bezelStyle = .glass }
        #endif
        return ceil(button.fittingSize.height)
    }()
    static let textFieldInsets: CGFloat = 4
    static let minimumCollapsedWidth: CGFloat = 100
    static let maximumCollapsedWidth: CGFloat = 340
    static let minimumExpandedWidth: CGFloat = 230
    static let maximumExpandedWidth: CGFloat = 480
    static var horizontalInsets: CGFloat { horizontalPadding * 2 }
    static var headerOnlyHeight: CGFloat { verticalPadding * 2 + headerHeight }
    static var expandedInsets: CGFloat { headerOnlyHeight + headerGap + buttonGap + buttonHeight }
}

func questionBubbleSize(text: String, title: String, expanded: Bool, screen: CGSize) -> CGSize {
    let available = CGSize(width: max(1, screen.width - 12), height: max(1, screen.height - 12))
    let titleWidth = ceil((title as NSString).size(withAttributes: [.font: BubbleMetrics.headerFont]).width) + BubbleMetrics.textFieldInsets
    if !expanded {
        let previewWidth = ceil((attentionQuestionPreview(text) as NSString).size(withAttributes: [.font: BubbleMetrics.bodyFont]).width) + BubbleMetrics.textFieldInsets
        let width = min(available.width, BubbleMetrics.maximumCollapsedWidth,
                        max(BubbleMetrics.minimumCollapsedWidth, max(titleWidth, previewWidth) + BubbleMetrics.horizontalInsets))
        let height = BubbleMetrics.headerOnlyHeight + (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : BubbleMetrics.headerGap + BubbleMetrics.previewHeight)
        return CGSize(width: width, height: min(available.height, height))
    }
    let body = joinedQuestionLines(text)
    let lineWidth = body.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: BubbleMetrics.bodyFont]).width }.max() ?? 0
    let width = min(available.width, BubbleMetrics.maximumExpandedWidth,
                    max(BubbleMetrics.minimumExpandedWidth, ceil(lineWidth) + BubbleMetrics.horizontalInsets,
                        min(BubbleMetrics.maximumCollapsedWidth, titleWidth + BubbleMetrics.horizontalInsets)))
    let measured = (body as NSString).boundingRect(with: CGSize(width: max(1, width - BubbleMetrics.horizontalInsets), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: BubbleMetrics.bodyFont])
    return CGSize(width: width, height: min(available.height, max(BubbleMetrics.previewHeight, ceil(measured.height)) + BubbleMetrics.expandedInsets))
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

struct BubblePointerState {
    let inside: Bool
    let holds: Bool
}

func bubblePointerState(frame: CGRect, pointer: CGPoint, previousPointer: CGPoint? = nil) -> BubblePointerState {
    let inside = frame.contains(pointer)
    let moved = previousPointer != nil && previousPointer != pointer
    return BubblePointerState(inside: inside, holds: inside || (moved && frame.insetBy(dx: -24, dy: -24).contains(pointer)))
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
        bezelStyle = .rounded
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { bezelStyle = .glass }
        #endif
        font = BubbleMetrics.buttonFont
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

private func bubbleBackground(for surface: NSView) -> NSView {
    // Apple ships Swift 6.2 with the macOS 26 SDK. Keep older compilers on the fallback.
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = BubbleMetrics.cornerRadius
        glass.contentView = surface
        return glass
    }
    #endif
    let effect = NSVisualEffectView()
    effect.material = .popover
    effect.blendingMode = .behindWindow
    effect.state = .active
    let radius = BubbleMetrics.cornerRadius
    let size = CGSize(width: radius * 2 + 1, height: radius * 2 + 1)
    let mask = NSImage(size: size, flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    mask.resizingMode = .stretch
    effect.maskImage = mask
    effect.addSubview(surface)
    return effect
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
    var pointerInside = false
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
        surface.hover = hover; surface.click = focus
        surface.autoresizingMask = [.width, .height]
        panel.contentView = bubbleBackground(for: surface)
        open = BubbleButton("Open agent", action: focus)
        surface.body = text; surface.openControl = open
        header.font = BubbleMetrics.headerFont
        header.textColor = .labelColor
        header.lineBreakMode = .byTruncatingTail
        header.maximumNumberOfLines = 1
        preview.font = BubbleMetrics.bodyFont
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = questionPreviewLineCount
        preview.lineBreakMode = .byTruncatingTail
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = BubbleMetrics.bodyFont
        text.textColor = .labelColor; text.textContainerInset = CGSize(width: 0, height: 0)
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
        if !canExpand && !body.isEmpty { pointerInside = false }
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
        surface.frame = panel.contentView?.bounds ?? CGRect(origin: .zero, size: rect.size)
        let x = BubbleMetrics.horizontalPadding
        let contentWidth = max(1, width - BubbleMetrics.horizontalInsets)
        let headerY = height - BubbleMetrics.verticalPadding - BubbleMetrics.headerHeight
        header.frame = CGRect(x: x, y: headerY, width: contentWidth, height: BubbleMetrics.headerHeight)
        preview.frame = CGRect(x: x, y: BubbleMetrics.verticalPadding, width: contentWidth, height: BubbleMetrics.previewHeight)
        let bodyY = BubbleMetrics.verticalPadding + BubbleMetrics.buttonHeight + BubbleMetrics.buttonGap
        scroll.frame = CGRect(x: x, y: bodyY, width: contentWidth, height: max(1, height - BubbleMetrics.expandedInsets))
        text.setFrameSize(CGSize(width: max(1, scroll.contentSize.width), height: max(text.frame.height, scroll.contentSize.height)))
        text.textContainer?.containerSize = CGSize(width: max(1, scroll.contentSize.width), height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.sizeToFit()
        open.frame = CGRect(x: x, y: BubbleMetrics.verticalPadding, width: min(BubbleMetrics.buttonWidth, contentWidth), height: BubbleMetrics.buttonHeight)
    }
}

final class SpeechBubbles {
    private var bubbles: [String: SpeechBubble] = [:]
    private var selected: String?
    private var agents: [String: Agent] = [:]
    private var focusError: (id: String, message: String)?
    private var collapseTask: DispatchWorkItem?
    private var refresh: (() -> Void)?
    private var previousPointer: CGPoint?

    func holdsPet(_ id: String, pointer: CGPoint) -> Bool {
        guard let bubble = bubbles[id], bubble.panel.isVisible else { return false }
        return bubblePointerState(frame: bubble.panel.frame, pointer: pointer, previousPointer: previousPointer).holds
    }

    func hideAll() {
        collapseTask?.cancel(); collapseTask = nil
        bubbles.values.forEach { $0.panel.orderOut(nil) }
        bubbles.removeAll(); agents.removeAll(); selected = nil; focusError = nil; refresh = nil; previousPointer = nil
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
        let pointer = NSEvent.mouseLocation
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
                let containedPointer = bubble.panel.frame.contains(pointer) ? pointer : nil
                rect = expandedBubbleRect(from: anchor, size: size, screen: screen, previous: bubble.expandedFrame, pointer: containedPointer)
                bubble.expandedFrame = rect
            } else if !bubble.expanded, let anchor = bubble.anchor {
                let placement = bubble.expandedFrame ?? anchor
                let collapsed = CGRect(x: placement.minX, y: placement.maxY - size.height, width: size.width, height: size.height)
                rect = expandedBubbleRect(from: collapsed, size: size, screen: screen)
                bubble.anchor = nil; bubble.expandedFrame = nil
            } else if holdsPet(id, pointer: pointer) {
                let held = CGRect(origin: bubble.panel.frame.origin, size: size)
                rect = expandedBubbleRect(from: held, size: size, screen: screen)
            } else { rect = bubbleRect(above: head, size: size, screen: screen, occupied: occupied) }
            occupied.append(rect)
            bubble.layout(in: rect)
            if !bubble.panel.isVisible { bubble.panel.orderFrontRegardless() }
        }
        previousPointer = pointer
        // Panel movement and tracking-area replacement can miss AppKit enter events.
        for (id, bubble) in bubbles where bubble.panel.isVisible {
            let inside = bubblePointerState(frame: bubble.panel.frame, pointer: pointer).inside
            if inside != bubble.pointerInside { hover(id, inside: inside) }
        }
    }

    private func hover(_ id: String, inside: Bool) {
        guard let bubble = bubbles[id], bubble.pointerInside != inside else { return }
        bubble.pointerInside = inside
        guard bubble.canExpand else { return }
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
