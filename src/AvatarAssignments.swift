import AppKit

struct AvatarChoice {
    let token: String
    let name: String
    let image: NSImage
}

final class AvatarAssignmentTile: NSButton, NSPopoverDelegate {
    let choices: [AvatarChoice]
    let inherited: [AvatarChoice]
    private(set) var selection: [String]
    var scopeLabel = ""
    var choose: (([String]) -> Void)?
    var inspect: (() -> Void)?
    var didClosePicker: (() -> Void)?
    var isEditing: Bool { picker != nil }
    private var dropHighlighted = false
    private var picker: NSPopover?

    init(choices: [AvatarChoice], selection: [String], inherited: [AvatarChoice]) {
        self.choices = choices; self.selection = selection; self.inherited = inherited
        super.init(frame: CGRect(x: 0, y: 0, width: 150, height: 100))
        title = ""; isBordered = false; setButtonType(.momentaryChange)
        target = self; action = #selector(openPicker)
        registerForDraggedTypes([petDragType])
        identifier = NSUserInterfaceItemIdentifier("assignment-grid-tile")
        toolTip = "Drop a pet to add it. Click to edit this pet pool."
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 100) }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var shown: [AvatarChoice] {
        selection.isEmpty ? inherited : selection.compactMap { token in choices.first { $0.token == token } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = !selection.isEmpty
        let active = dropHighlighted || window?.firstResponder === self
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        (selected || active ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.controlBackgroundColor).setFill()
        shape.fill()
        (selected || active ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = active ? 3 : selected ? 2 : 1
        shape.stroke()
        let pictures = Array(shown.prefix(4))
        let side: CGFloat = pictures.count == 1 ? 44 : pictures.count == 2 ? 40 : pictures.count == 3 ? 36 : 28
        let total = CGFloat(pictures.count) * side + CGFloat(max(0, pictures.count - 1)) * 3
        for (index, choice) in pictures.enumerated() {
            let fit = min(side / max(1, choice.image.size.width), 44 / max(1, choice.image.size.height))
            let size = CGSize(width: choice.image.size.width * fit, height: choice.image.size.height * fit)
            let x = (bounds.width - total) / 2 + CGFloat(index) * (side + 3) + (side - size.width) / 2
            choice.image.draw(in: CGRect(x: x, y: 33 + (44 - size.height) / 2, width: size.width, height: size.height),
                              from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.45, respectFlipped: true, hints: nil)
        }
        let headerStyle = NSMutableParagraphStyle(); headerStyle.alignment = .center; headerStyle.lineBreakMode = .byTruncatingTail
        (scopeLabel as NSString).draw(in: CGRect(x: 6, y: 83, width: bounds.width - 12, height: 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: headerStyle])
        let count = selected ? selection.count : shown.count
        let name = count == 1 ? (shown.first?.name ?? "Pet") : selected ? "\(count) pets" : "\(count) possible pets"
        let alignment = NSMutableParagraphStyle(); alignment.alignment = .center; alignment.lineBreakMode = .byTruncatingTail
        (name as NSString).draw(in: CGRect(x: 6, y: 19, width: bounds.width - 12, height: 17), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: alignment])
        let note = selected ? (count > 4 ? "+\(count - 4) more in pool" : count == 1 ? "Assigned" : "Your pool") : "From rules"
        (note as NSString).draw(in: CGRect(x: 6, y: 4, width: bounds.width - 12, height: 15), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor, .paragraphStyle: alignment])
    }

    @objc func inspectScope() { inspect?() }
    @objc private func openPicker() {
        inspectScope()
        let editor = AvatarPoolPicker(choices: choices, selection: selection)
        let popover = NSPopover(); popover.behavior = .transient; popover.delegate = self
        popover.contentViewController = editor; popover.contentSize = NSSize(width: 430, height: 470)
        editor.change = { [weak self] tokens in self?.commit(tokens) }
        editor.complete = { [weak popover] in popover?.close() }
        picker = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        picker = nil
        didClosePicker?()
    }

    private func commit(_ tokens: [String]) {
        var seen: Set<String> = []
        let allowed = Set(choices.map(\.token))
        selection = tokens.filter { allowed.contains($0) && seen.insert($0).inserted }
        needsDisplay = true
        choose?(selection)
    }

    private func dropToken(_ pasteboard: NSPasteboard) -> String? {
        guard isEnabled, let token = pasteboard.string(forType: petDragType), choices.contains(where: { $0.token == token }) else { return nil }
        return token
    }

    @discardableResult
    func acceptDrop(from pasteboard: NSPasteboard) -> Bool {
        guard let token = dropToken(pasteboard) else { return false }
        commit(selection + [token])
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHighlighted = dropToken(sender.draggingPasteboard) != nil
        needsDisplay = true
        return dropHighlighted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlighted = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropToken(sender.draggingPasteboard) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlighted = false; needsDisplay = true
        return acceptDrop(from: sender.draggingPasteboard)
    }
}

private final class AvatarPoolPicker: NSViewController, NSSearchFieldDelegate {
    let choices: [AvatarChoice]
    private var selection: [String]
    var complete: (() -> Void)?
    var change: (([String]) -> Void)?
    private let search = NSSearchField()
    private let heading = NSTextField(labelWithString: "")
    private var scroll: NSScrollView!

    init(choices: [AvatarChoice], selection: [String]) {
        self.choices = choices; self.selection = selection
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 430, height: 470))
        view.wantsLayer = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        view.identifier = NSUserInterfaceItemIdentifier("avatar-pool-picker")
        heading.frame = CGRect(x: 12, y: 438, width: 406, height: 20)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let note = NSTextField(labelWithString: "Each agent keeps one pet from this pool.")
        note.frame = CGRect(x: 12, y: 416, width: 406, height: 18); note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 11)
        search.frame = CGRect(x: 12, y: 380, width: 406, height: 28)
        search.placeholderString = "Find a pet"; search.delegate = self
        scroll = studioScroll(NSView()); scroll.frame = CGRect(x: 12, y: 55, width: 406, height: 315)
        scroll.hasHorizontalScroller = false
        let reset = StudioButton("Use rules") { [weak self] in self?.change?([]); self?.complete?() }
        reset.frame = CGRect(x: 12, y: 12, width: 120, height: 30)
        let all = StudioButton("Select all") { [weak self] in
            guard let self else { return }
            self.selection = self.choices.map(\.token); self.change?(self.selection); self.rebuild()
        }
        all.frame = CGRect(x: 145, y: 12, width: 120, height: 30)
        let done = StudioButton("Done") { [weak self] in self?.complete?() }
        done.frame = CGRect(x: 330, y: 12, width: 88, height: 30); done.keyEquivalent = "\r"
        for child in [heading, note, search, scroll!, reset, all, done] { view.addSubview(child) }
        rebuild(resetScroll: true)
    }

    func controlTextDidChange(_ obj: Notification) { rebuild(resetScroll: true) }

    private func toggle(_ token: String) {
        if selection.contains(token) { selection.removeAll { $0 == token } }
        else { selection.append(token) }
        change?(selection)
        rebuild()
    }

    private func rebuild(resetScroll: Bool = false) {
        let previousOrigin = scroll.contentView.bounds.origin
        heading.stringValue = selection.isEmpty ? "Use existing rules, or choose pets" : "\(selection.count) selected"
        let visible = choices.filter { search.stringValue.isEmpty || $0.name.localizedCaseInsensitiveContains(search.stringValue) }
        var rows: [[NSView]] = []
        for start in stride(from: 0, to: visible.count, by: 4) {
            var row: [NSView] = visible[start..<min(start + 4, visible.count)].map { choice in
                let button = AvatarPoolOption(choice: choice, selected: selection.contains(choice.token)) { [weak self] in self?.toggle(choice.token) }
                button.widthAnchor.constraint(equalToConstant: 86).isActive = true; button.heightAnchor.constraint(equalToConstant: 82).isActive = true
                button.toolTip = choice.name; button.setAccessibilityLabel(choice.name)
                button.identifier = NSUserInterfaceItemIdentifier("pet-choice:" + choice.token)
                return button
            }
            while row.count < 4 { row.append(NSView()) }
            rows.append(row)
        }
        let grid = NSGridView(views: rows.isEmpty ? [[NSTextField(labelWithString: "No matching pets")]] : rows)
        grid.columnSpacing = 10; grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.setFrameSize(grid.fittingSize); scroll.documentView = grid
        scroll.contentView.scroll(to: CGPoint(x: 0, y: resetScroll ? max(0, grid.frame.height - scroll.contentSize.height) : min(previousOrigin.y, max(0, grid.frame.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

private final class AvatarPoolOption: NSButton {
    private let choice: AvatarChoice
    private let selected: Bool
    private let invoke: () -> Void
    init(choice: AvatarChoice, selected: Bool, invoke: @escaping () -> Void) {
        self.choice = choice; self.selected = selected; self.invoke = invoke
        super.init(frame: .zero)
        title = choice.name; isBordered = false; target = self; action = #selector(run)
        setAccessibilityValue(selected ? 1 : 0)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }
    @objc private func run() { invoke() }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill(); shape.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke(); shape.lineWidth = selected ? 2 : 1; shape.stroke()
        let fit = min(50 / max(1, choice.image.size.width), 50 / max(1, choice.image.size.height))
        let size = CGSize(width: choice.image.size.width * fit, height: choice.image.size.height * fit)
        choice.image.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: 24 + (50 - size.height) / 2, width: size.width, height: size.height))
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
        (choice.name as NSString).draw(in: CGRect(x: 4, y: 5, width: bounds.width - 8, height: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        if selected {
            ("✓" as NSString).draw(in: CGRect(x: bounds.width - 17, y: bounds.height - 17, width: 13, height: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.controlAccentColor])
        }
    }
}
