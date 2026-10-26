import AppKit

let petDragType = NSPasteboard.PasteboardType("dev.herdr-pets.character")

final class StudioButton: NSButton {
    var invoke: (() -> Void)?
    convenience init(_ title: String, _ invoke: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.invoke = invoke; target = self; action = #selector(run)
    }
    @objc private func run() { invoke?() }
}

private final class StudioSlider: NSSlider {
    var changed: ((Double) -> Void)?
    convenience init(_ value: Double, _ range: ClosedRange<Double>, changed: @escaping (Double) -> Void) {
        self.init(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.changed = changed; target = self; action = #selector(updateValue)
    }
    @objc private func updateValue() { changed?(doubleValue) }
}

private final class PetTile: NSView, NSDraggingSource {
    let token: String
    let title: String
    let image: NSImage
    init(token: String, title: String, image: NSImage) {
        self.token = token; self.title = title; self.image = image
        super.init(frame: CGRect(x: 0, y: 0, width: 180, height: 54))
        toolTip = "Drag \(title) into an assignment cell"
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let fit = min(44 / max(1, image.size.width), 44 / max(1, image.size.height))
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        image.draw(in: CGRect(x: 8 + (44 - size.width) / 2, y: 4 + (44 - size.height) / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        (title as NSString).draw(in: CGRect(x: 60, y: 18, width: 112, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
    }
    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem(); item.setString(token, forType: petDragType)
        let drag = NSDraggingItem(pasteboardWriter: item)
        drag.setDraggingFrame(CGRect(x: 0, y: 0, width: 48, height: 48), contents: image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

final class AssignmentCell: NSPopUpButton {
    var choose: ((String?) -> Void)?
    var inspect: (() -> Void)?
    var firstIsPlaceholder = false
    var allowed: Set<String> = []
    var tokens: [String?] = []
    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        registerForDraggedTypes([petDragType]); target = self; action = #selector(selectPet)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { inspect?(); super.mouseDown(with: event) }
    @objc private func selectPet() {
        guard tokens.indices.contains(indexOfSelectedItem), !(firstIsPlaceholder && indexOfSelectedItem == 0) else { return }
        choose?(tokens[indexOfSelectedItem])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let token = sender.draggingPasteboard.string(forType: petDragType), allowed.contains(token) else { return [] }
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let token = sender.draggingPasteboard.string(forType: petDragType), allowed.contains(token) else { return false }
        choose?(token); return true
    }
}

private func studioText(_ text: String, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: 12)
    field.textColor = secondary ? .secondaryLabelColor : .labelColor
    return field
}

private func studioStack(_ views: [NSView], vertical: Bool = true) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = vertical ? .vertical : .horizontal
    stack.alignment = vertical ? .leading : .centerY
    stack.spacing = 12
    stack.distribution = .fill
    return stack
}

private final class StudioScroll: NSScrollView {
    private var previousTop: CGFloat?
    override func layout() {
        let wasAtTop = previousTop.map { abs(contentView.bounds.minY - $0) < 1 } ?? true
        super.layout()
        guard let documentView else { return }
        let fit = documentView.fittingSize
        let wanted = CGSize(width: max(fit.width, contentView.bounds.width), height: max(fit.height, contentView.bounds.height))
        if documentView.frame.size != wanted { documentView.setFrameSize(wanted) }
        let top: CGFloat = documentView.isFlipped ? 0 : max(0, wanted.height - contentView.bounds.height)
        if wasAtTop { contentView.scroll(to: CGPoint(x: contentView.bounds.minX, y: top)); reflectScrolledClipView(contentView) }
        previousTop = top
    }
}

func studioScroll(_ document: NSView) -> NSScrollView {
    let scroll = StudioScroll()
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false; scroll.documentView = document
    document.translatesAutoresizingMaskIntoConstraints = true
    document.setFrameSize(document.fittingSize)
    scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return scroll
}

final class PetStudio: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    private let roles: RolePets
    private var window: NSWindow?
    private var draft = AssignmentDocument()
    private var expected: Data?
    private var settings = Preferences()
    private var overrides: [String: String] = [:]
    private var agentType = ""
    private var selectedScope: (repository: String, role: String)?
    private var activateAssignmentsOnApply = false
    private let modeHint = studioText("", secondary: true)
    private var activateButton: NSButton?
    private var individualPopover: NSPopover?

    private let palette = NSStackView()
    private let gridHost = NSView()
    private let sizesHost = NSView()
    private let details = studioText("Choose a cell to see its rule and affected agents.", secondary: true)
    private let errorLabel = studioText("")
    private let search = NSSearchField()
    private var entries: [(token: String, name: String, image: NSImage)] = []
    private var currentTab = 0
    private var tabs: NSTabView?
    private var tabSelector: NSSegmentedControl?

    init(roles: RolePets) { self.roles = roles }

    func show() {
        if let window { updateModeHint(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        roles.reload()
        draft = roles.assignments.load(); expected = roles.assignments.snapshot
        settings = preferences; overrides = roles.agentOverrides
        selectedScope = nil; activateAssignmentsOnApply = false
        entries = PetKind.allCases.map { ("builtin:" + $0.rawValue, $0.title, Sprites.thumbnail($0)) }
        entries += roles.customIDs.compactMap { id in roles.thumbnail(id).map { ("custom:" + id, $0.title, $0.image) } }
        let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1080, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Pet Studio"; w.isReleasedWhenClosed = false; w.contentMinSize = CGSize(width: 740, height: 520)
        w.setFrameAutosaveName("HerdrPetStudio"); w.delegate = self
        let tabs = NSTabView()
        tabs.tabViewType = .noTabsNoBorder
        self.tabs = tabs
        let selector = NSSegmentedControl(labels: ["Assignments", "Sizes", "Behavior"], trackingMode: .selectOne, target: self, action: #selector(selectTab(_:)))
        selector.selectedSegment = currentTab
        tabSelector = selector
        for (index, title) in ["Assignments", "Sizes", "Behavior"].enumerated() {
            let item = NSTabViewItem(identifier: index); item.label = title
            item.view = index == 0 ? assignmentsView() : index == 1 ? sizesHost : behaviorView()
            item.view?.autoresizingMask = [.width, .height]
            tabs.addTabViewItem(item)
        }
        tabs.selectTabViewItem(at: currentTab)
        let actions = studioStack([
            StudioButton("Reload") { [weak self] in self?.reloadDraft() },
            errorLabel,
            StudioButton("Cancel") { [weak self] in self?.window?.close() },
            StudioButton("Apply") { [weak self] in self?.apply() }
        ], vertical: false)
        errorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.arrangedSubviews.first?.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let content = studioStack([selector, tabs, actions])
        content.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -16),
            tabs.widthAnchor.constraint(equalTo: content.widthAnchor),
            actions.widthAnchor.constraint(equalTo: content.widthAnchor),
            tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 380)
        ])
        details.identifier = NSUserInterfaceItemIdentifier("selected-rule-summary")
        details.maximumNumberOfLines = 3; details.lineBreakMode = .byTruncatingTail
        details.heightAnchor.constraint(equalToConstant: 48).isActive = true
        errorLabel.maximumNumberOfLines = 2
        window = w
        refreshPalette(); refreshGrid(); refreshSizes()
        errorLabel.stringValue = roles.assignments.lastError ?? ""
        w.contentView?.layoutSubtreeIfNeeded()
        if let screen = w.screen ?? NSScreen.main {
            let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            var frame = w.frame
            frame.size = CGSize(width: min(frame.width, safe.width), height: min(frame.height, safe.height))
            frame.origin = CGPoint(x: min(max(frame.minX, safe.minX), safe.maxX - frame.width), y: min(max(frame.minY, safe.minY), safe.maxY - frame.height))
            w.setFrame(frame, display: false)
        }
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectTab(_ sender: NSSegmentedControl) { currentTab = sender.selectedSegment; tabs?.selectTabViewItem(at: currentTab) }

    func windowWillClose(_ notification: Notification) { window = nil }

    func exportPreviews(to directory: URL) throws {
        guard let view = window?.contentView, let tabs = self.tabs else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<tabs.numberOfTabViewItems {
            tabs.selectTabViewItem(at: index)
            tabSelector?.selectedSegment = index
            view.layoutSubtreeIfNeeded()
            func prepare(_ node: NSView) {
                if let scroll = node as? StudioScroll { scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded() }
                node.subviews.forEach(prepare)
            }
            prepare(view)
            view.wantsLayer = true
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                window?.displayIfNeeded()
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("studio-\(index).png"))
        }
    }

    private func assignmentsView() -> NSView {
        search.placeholderString = "Find a pet"; search.delegate = self
        palette.orientation = .vertical; palette.alignment = .leading; palette.spacing = 4
        let paletteView = studioStack([search, studioScroll(palette)])
        paletteView.widthAnchor.constraint(equalToConstant: 198).isActive = true
        search.widthAnchor.constraint(equalTo: paletteView.widthAnchor).isActive = true
        paletteView.arrangedSubviews.last!.widthAnchor.constraint(equalTo: paletteView.widthAnchor).isActive = true
        let types = NSPopUpButton()
        types.addItem(withTitle: "All agent types"); types.lastItem?.representedObject = ""
        for type in knownTypes { types.addItem(withTitle: type.capitalized + " only"); types.lastItem?.representedObject = type }
        types.selectItem(at: agentType.isEmpty ? 0 : (knownTypes.firstIndex(of: agentType) ?? -1) + 1)
        types.target = self; types.action = #selector(selectType(_:))
        types.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let suggestions = NSPopUpButton(); suggestions.addItems(withTitles: ["Add a live repository…"] + Array(Set(scene.agents.compactMap(\.cwd))).sorted())
        suggestions.widthAnchor.constraint(equalToConstant: 190).isActive = true
        suggestions.target = self; suggestions.action = #selector(addSuggestion(_:))
        let scopeLabel = studioText("Applies to")
        scopeLabel.setContentHuggingPriority(.required, for: .horizontal)
        let tools = studioStack([scopeLabel, types, StudioButton("Add role…") { [weak self] in self?.addRole() }, suggestions, NSView()], vertical: false)
        tools.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let hint = studioText("Drop a pet onto a tile to add it. Click a tile to choose several pets.", secondary: true)
        hint.maximumNumberOfLines = 2; hint.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let activate = StudioButton("Use assignments") { [weak self] in self?.activateAssignmentsOnApply = true; self?.updateModeHint() }
        activateButton = activate
        let mode = studioStack([modeHint, activate, NSView()], vertical: false)
        mode.heightAnchor.constraint(equalToConstant: 28).isActive = true
        modeHint.maximumNumberOfLines = 2
        updateModeHint()
        let path = NSTextField(); path.placeholderString = "Add a repository or folder path"
        path.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        path.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let addPath = StudioButton("Add path") { [weak self, weak path] in
            guard let self, let text = path?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            guard text.hasPrefix("/") || text == "~" || text.hasPrefix("~/") else { self.errorLabel.stringValue = "Use an absolute path or ~/ path."; return }
            self.draft.repositories.append(text); path?.stringValue = ""; self.refreshGrid()
        }
        let browse = StudioButton("Choose folder…") { [weak self] in
            let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
            if picker.runModal() == .OK, let path = picker.url?.path { self?.draft.repositories.append(path); self?.refreshGrid() }
        }
        let paths = studioStack([path, addPath, browse], vertical: false)
        paths.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let individuals = NSButton(title: "Individual agents…", target: self, action: #selector(showIndividuals(_:)))
        individuals.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let right = studioStack([tools, hint, mode, paths, gridHost, individuals, details])
        gridHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        gridHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        for view in [tools, hint, mode, paths, gridHost, details] { view.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true }
        let all = studioStack([paletteView, right], vertical: false); all.alignment = .top
        right.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -222).isActive = true
        paletteView.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
        right.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
        return all
    }

    private func updateModeHint() {
        if activateAssignmentsOnApply { modeHint.stringValue = "Apply will use these assignments in Custom mode." }
        else if preferences.characterMode == .custom { modeHint.stringValue = "Custom assignments are active. The first row sets defaults." }
        else { modeHint.stringValue = "\(preferences.characterMode.title) mode is active. These assignments are off." }
        activateButton?.isHidden = activateAssignmentsOnApply || preferences.characterMode == .custom
    }

    @objc private func showIndividuals(_ sender: NSButton) {
        let live = studioStack(scene.agents.map { agent -> NSView in
            let picker = AssignmentCell(frame: .zero, pullsDown: false)
            picker.addItem(withTitle: "Use grid and rules"); picker.tokens = [nil]
            for entry in entries { picker.addItem(withTitle: entry.name); picker.tokens.append(entry.token); picker.lastItem?.image = entry.image }
            if let key = agent.sessionKey, let token = overrides[key], let index = picker.tokens.firstIndex(where: { $0 == token }) { picker.selectItem(at: index) }
            picker.isEnabled = agent.sessionKey != nil; picker.allowed = Set(entries.map(\.token))
            picker.widthAnchor.constraint(equalToConstant: 155).isActive = true
            picker.choose = { [weak self] token in if let key = agent.sessionKey { self?.overrides[key] = token } }
            let label = studioText("\(agent.machine == "local" ? "Local" : "Remote") · \(agent.label ?? agent.agent ?? "Agent")\n\(agent.cwd ?? "No repository")")
            label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(equalToConstant: 380).isActive = true
            label.toolTip = (agent.label ?? "Agent") + "\n" + (agent.cwd ?? "")
            return studioStack([label, picker], vertical: false)
        })
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 420))
        let note = studioText("Change one agent here. Apply keeps the choice for its current session.", secondary: true)
        note.frame = CGRect(x: 12, y: 376, width: 576, height: 32)
        let scroll = studioScroll(live); scroll.frame = CGRect(x: 12, y: 12, width: 576, height: 352)
        root.addSubview(note); root.addSubview(scroll)
        let popover = NSPopover(); popover.behavior = .transient
        let controller = NSViewController(); controller.view = root; popover.contentViewController = controller
        popover.contentSize = root.frame.size; individualPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private var knownTypes: [String] { Array(Set(["claude", "codex", agentType] + draft.cells.map(\.agentType) + scene.agents.compactMap(\.agent) + roles.legacyRules.flatMap { $0.agent ?? [] })).filter { !$0.isEmpty }.sorted() }
    private var knownRoles: [String] { Array(Set(draft.roles + draft.cells.map(\.role) + roles.legacyRules.flatMap { $0.role ?? [] } + scene.agents.compactMap { roleWord($0.label) })).filter { !$0.isEmpty }.sorted() }
    private var repositories: [String] { [""] + Array(Set((draft.repositories + draft.cells.map(\.repository) + roles.legacyRules.flatMap { $0.cwd ?? [] }).map { AssignmentStore.prefix($0, home: NSHomeDirectory()) })).filter { !$0.isEmpty }.sorted() }

    @objc private func selectType(_ sender: NSPopUpButton) { agentType = sender.selectedItem?.representedObject as? String ?? ""; selectedScope = nil; refreshGrid() }
    @objc private func addSuggestion(_ sender: NSPopUpButton) { if sender.indexOfSelectedItem > 0 { draft.repositories.append(sender.titleOfSelectedItem!); refreshGrid(); sender.selectItem(at: 0) } }
    func controlTextDidChange(_ obj: Notification) { refreshPalette() }

    private func refreshPalette() {
        palette.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in entries where search.stringValue.isEmpty || entry.name.localizedCaseInsensitiveContains(search.stringValue) {
            let tile = PetTile(token: entry.token, title: entry.name, image: entry.image)
            tile.widthAnchor.constraint(equalToConstant: 180).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 54).isActive = true
            palette.addArrangedSubview(tile)
        }
        palette.enclosingScrollView?.needsLayout = true
    }

    private func fill(_ host: NSView, with view: NSView) {
        host.subviews.forEach { $0.removeFromSuperview() }
        host.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor), view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
    }

    private func choice(_ token: String) -> AvatarChoice {
        if let entry = entries.first(where: { $0.token == token }) { return AvatarChoice(token: token, name: entry.name, image: entry.image) }
        let title = token.hasPrefix("custom:") ? String(token.dropFirst(7)) : token
        return AvatarChoice(token: token, name: title, image: NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: "Missing pet") ?? NSImage(size: NSSize(width: 32, height: 32)))
    }

    private func refreshGrid() {
        let previous = (gridHost.subviews.first as? NSScrollView)?.contentView.bounds.origin
        let paths = repositories, roles = knownRoles, types = knownTypes
        struct Scenario: Hashable { let path: String; let role: String; let type: String }
        var previews: [Scenario: Set<String>] = [:]
        func inheritedChoices(repository: String, role: String, excludingCell: Bool) -> [String] {
            var document = draft
            if excludingCell { document.set(nil, repository: repository, role: role, agentType: agentType) }
            var tokens: Set<String> = []
            let scenarios = repository.isEmpty ? paths.filter { !$0.isEmpty } + ["/other"] : [repository] + paths.filter { $0.hasPrefix(repository + "/") }
            for path in scenarios { for type in agentType.isEmpty ? types : [agentType] { for word in role.isEmpty ? roles + ["other"] : [role] {
                let key = Scenario(path: path, role: word, type: type)
                if !excludingCell, let saved = previews[key] { tokens.formUnion(saved); continue }
                let agent = Agent(terminal_id: "preview", agent_status: "idle", agent: type, label: word, cwd: AssignmentStore.prefix(path, home: NSHomeDirectory()))
                var choices: Set<String> = []
                if let winner = AssignmentStore.winner(for: agent, document: document, home: NSHomeDirectory()) { choices.formUnion(winner.pets) }
                else if let rule = self.roles.legacyRules.first(where: { $0.matches(agent, home: NSHomeDirectory()) }) {
                    if rule.pet == "generic" { choices.formUnion(PetKind.generic.map { "builtin:" + $0.rawValue }) }
                    else { switch self.roles.resolve(rule.pet, for: agent) { case .builtin(let kind): choices.insert("builtin:" + kind.rawValue); case .custom(let id, _): choices.insert("custom:" + id) } }
                } else { choices.insert("builtin:" + petKind(ofType: type).rawValue) }
                if !excludingCell { previews[key] = choices }
                tokens.formUnion(choices)
            } } }
            return tokens.sorted()
        }
        var rows: [[NSView]] = [[studioText("Repository / role")] + ([""] + roles).map { studioText($0.isEmpty ? "All roles" : $0.capitalized) }]
        for repository in paths {
            let title = repository.isEmpty ? "All repositories" : repository.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: .anchored)
            let label = studioText(title); label.maximumNumberOfLines = 3; label.lineBreakMode = .byTruncatingMiddle; label.toolTip = repository
            rows.append([label] + ([""] + roles).map { role -> NSView in
                let explicit = draft.cells.first { AssignmentStore.prefix($0.repository, home: NSHomeDirectory()) == repository && $0.role == role && $0.agentType == agentType }
                let selection = explicit?.pets ?? []
                let inherited = inheritedChoices(repository: repository, role: role, excludingCell: explicit != nil).map(choice)
                let options = entries.map { AvatarChoice(token: $0.token, name: $0.name, image: $0.image) } + selection.filter { token in !entries.contains { $0.token == token } }.map(choice)
                let tile = AvatarAssignmentTile(choices: options, selection: selection, inherited: inherited)
                tile.scopeLabel = role.isEmpty ? "All roles" : role.capitalized
                tile.widthAnchor.constraint(equalToConstant: 150).isActive = true
                tile.heightAnchor.constraint(equalToConstant: 100).isActive = true
                tile.setAccessibilityLabel("\(title), \(role.isEmpty ? "All roles" : role), \(agentType.isEmpty ? "All types" : agentType): \(selection.isEmpty ? "From rules" : selection.map(name).joined(separator: ", "))")
                tile.inspect = { [weak self] in self?.selectedScope = (repository, role); self?.describe(repository: repository, role: role) }
                tile.choose = { [weak self, weak tile] pool in
                    guard let self else { return }
                    self.draft.setPool(pool, repository: repository, role: role, agentType: self.agentType)
                    self.selectedScope = (repository, role)
                    if tile?.isEditing == true { self.describe(repository: repository, role: role) } else { self.refreshGrid() }
                }
                tile.didClosePicker = { [weak self] in self?.refreshGrid() }
                return tile
            })
        }
        let grid = NSGridView(views: rows); grid.rowSpacing = 10; grid.columnSpacing = 10
        grid.column(at: 0).width = 210
        let scroll = studioScroll(grid)
        fill(gridHost, with: scroll)
        gridHost.layoutSubtreeIfNeeded(); scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded()
        if let previous {
            let maximum = CGPoint(x: max(0, grid.frame.width - scroll.contentSize.width), y: max(0, grid.frame.height - scroll.contentSize.height))
            scroll.contentView.scroll(to: CGPoint(x: min(previous.x, maximum.x), y: min(previous.y, maximum.y)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if let scope = selectedScope { describe(repository: scope.repository, role: scope.role) }
        else { details.stringValue = "The first row sets defaults. Folder rows add exceptions.\nBlue tiles are your choices. Gray tiles use existing rules." }
    }

    private func name(_ token: String) -> String { entries.first { $0.token == token }?.name ?? token }

    private func describe(repository: String, role: String) {
        let rule = PetRule(role: role.isEmpty ? nil : [role], agent: agentType.isEmpty ? nil : [agentType], cwd: repository.isEmpty ? nil : [repository], pet: "")
        let count = scene.agents.filter { rule.matches($0, home: NSHomeDirectory()) }.count
        let explicit = draft.cells.first { AssignmentStore.prefix($0.repository, home: NSHomeDirectory()) == repository && $0.role == role && $0.agentType == agentType }
        let scope = "\(agentType.isEmpty ? "All agent types" : agentType.capitalized) · \(repository.isEmpty ? "All repositories" : repository.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: .anchored)) · \(role.isEmpty ? "All roles" : role)"
        let selected = explicit.map { $0.pets.count == 1 ? name($0.pet) : "\($0.pets.count) pets in this pool" } ?? "Uses existing rules"
        details.stringValue = scope + "\n" + selected + ". \(count) matching agents."
        details.toolTip = details.stringValue
    }

    private func addRole() {
        let alert = NSAlert(); alert.messageText = "Add a role"
        let input = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24)); alert.accessoryView = input
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !value.isEmpty && value.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) { draft.roles.append(value); refreshGrid() }
        }
    }

    private func refreshSizes() {
        let baseLabel = studioText("Base pet size: \(Int(settings.size)) pt")
        let boostLabel = studioText("Custom boost: \(settings.customPetSize)%")
        let base = StudioSlider(settings.size, Preferences.sizeRange) { [weak self] value in self?.settings.size = value; self?.refreshSizes() }
        base.isContinuous = false
        let boost = StudioSlider(Double(settings.customPetSize), 100...200) { [weak self] value in self?.settings.customPetSize = Int(value.rounded()); self?.refreshSizes() }
        boost.isContinuous = false
        let rows: [NSView] = roles.customIDs.map { id in
            let share = settings.customSizeShares[id] ?? roles.sizeShare(id)
            let percent = 100 + Double(settings.customPetSize - 100) * share
            let image = roles.thumbnail(id)!
            let comparison = SizeComparison(custom: image.image, share: percent / 100, size: settings.size)
            comparison.widthAnchor.constraint(equalToConstant: 300).isActive = true
            comparison.heightAnchor.constraint(equalToConstant: 170).isActive = true
            let slider = StudioSlider(share, 0...1) { [weak self] value in self?.settings.customSizeShares[id] = value; self?.refreshSizes() }
            slider.isContinuous = false
            slider.setAccessibilityLabel("\(image.title) share of custom size boost")
            let text = studioStack([studioText("\(image.title): \(Int((share * 100).rounded()))% share, \(Int(percent.rounded()))% resulting size"), slider,
                StudioButton("Reset \(image.title)") { [weak self] in self?.settings.customSizeShares[id] = nil; self?.refreshSizes() }])
            text.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
            return studioStack([comparison, text], vertical: false)
        }
        let content = studioStack([baseLabel, base, boostLabel, boost, StudioButton("Reset all size overrides") { [weak self] in self?.settings.customSizeShares = [:]; self?.refreshSizes() }] + rows)
        base.widthAnchor.constraint(equalToConstant: 500).isActive = true; boost.widthAnchor.constraint(equalTo: base.widthAnchor).isActive = true
        fill(sizesHost, with: studioScroll(content))
    }

    private func behaviorView() -> NSView {
        let modes = NSPopUpButton(); modes.addItems(withTitles: MovementMode.allCases.map(\.title))
        modes.selectItem(at: MovementMode.allCases.firstIndex(of: settings.movementMode)!)
        modes.target = self; modes.action = #selector(selectMovement(_:))
        let bubbles = NSButton(checkboxWithTitle: "Show question bubbles", target: self, action: #selector(selectBubbles(_:)))
        bubbles.state = settings.showQuestionBubbles ? .on : .off
        let reduced = NSButton(checkboxWithTitle: "Reduce motion", target: self, action: #selector(selectReduced(_:)))
        reduced.state = settings.reducedMotion ? .on : .off
        return studioStack([studioText("Movement mode"), modes,
            studioText("Broadway pets walk along the bottom of the selected screen. Attention pets follow screen edges in both modes."),
            bubbles, studioText("Turn bubbles off to use only the exclamation mark. This choice applies in both movement modes.", secondary: true),
            reduced, studioText("Attention varies between stationary custom animations. The done animation stays the same.", secondary: true)])
    }
    @objc private func selectMovement(_ sender: NSPopUpButton) { settings.movementMode = MovementMode.allCases[sender.indexOfSelectedItem] }
    @objc private func selectBubbles(_ sender: NSButton) { settings.showQuestionBubbles = sender.state == .on }
    @objc private func selectReduced(_ sender: NSButton) { settings.reducedMotion = sender.state == .on }

    private func reloadDraft() {
        roles.reload()
        draft = roles.assignments.load(); expected = roles.assignments.snapshot
        settings = preferences; overrides = roles.agentOverrides
        selectedScope = nil; activateAssignmentsOnApply = false
        entries = PetKind.allCases.map { ("builtin:" + $0.rawValue, $0.title, Sprites.thumbnail($0)) }
        entries += roles.customIDs.compactMap { id in roles.thumbnail(id).map { ("custom:" + id, $0.title, $0.image) } }
        tabs?.tabViewItems[2].view = behaviorView()
        tabs?.tabViewItems[2].view?.autoresizingMask = [.width, .height]
        refreshPalette(); refreshGrid(); refreshSizes(); errorLabel.stringValue = roles.assignments.lastError ?? ""
    }
    private func apply() {
        do {
            try roles.assignments.save(draft, expected: expected)
            expected = roles.assignments.snapshot
            var updated = preferences
            updated.size = settings.size; updated.customPetSize = settings.customPetSize
            updated.customSizeShares = settings.customSizeShares; updated.movementMode = settings.movementMode
            if activateAssignmentsOnApply { updated.characterMode = .custom }
            updated.reducedMotion = settings.reducedMotion; updated.showQuestionBubbles = settings.showQuestionBubbles
            do { try updated.saveChecked() }
            catch { errorLabel.stringValue = "Assignments saved. Cannot save size and behavior settings: " + error.localizedDescription; return }
            preferences = updated; activateAssignmentsOnApply = false; updateModeHint()
            let active = Set(scene.agents.compactMap(\.sessionKey))
            roles.agentOverrides = overrides.filter { active.contains($0.key) }
            roles.reload(); scene.apply(scene.agents); scene.wake(); restoreArea()
            errorLabel.stringValue = "Applied. Grid choices take effect in Custom mode."
        } catch { errorLabel.stringValue = error.localizedDescription }
    }
}

private final class SizeComparison: NSView {
    let custom: NSImage
    let share: Double
    let size: Double
    init(custom: NSImage, share: Double, size: Double) { self.custom = custom; self.share = share; self.size = size; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let baseline: CGFloat = 24
        let line = NSBezierPath(); line.move(to: CGPoint(x: 8, y: baseline)); line.line(to: CGPoint(x: bounds.width - 8, y: baseline)); line.stroke()
        let reference = Sprites.frames(.codex)[.resting]![0]
        let built = NSImage(cgImage: reference.image, size: reference.size)
        for (image, x, factor) in [(built, CGFloat(70), 1.0), (custom, CGFloat(215), share)] {
            let scale = size / Double(baseSize) * factor
            let rect = CGRect(x: x - image.size.width * scale / 2, y: baseline, width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: rect)
        }
        ("Default" as NSString).draw(at: CGPoint(x: 40, y: 2), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor])
        ("Custom" as NSString).draw(at: CGPoint(x: 190, y: 2), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }
}
