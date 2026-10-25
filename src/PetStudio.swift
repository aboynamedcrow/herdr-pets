import AppKit

private let petDragType = NSPasteboard.PasteboardType("dev.herdr-pets.character")

private final class StudioButton: NSButton {
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
        image.draw(in: CGRect(x: 8, y: 4, width: 44, height: 44), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
    private var firstLayout = true
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let fit = documentView.fittingSize
        let wanted = CGSize(width: max(fit.width, contentView.bounds.width), height: max(fit.height, contentView.bounds.height))
        if documentView.frame.size != wanted { documentView.setFrameSize(wanted) }
        if firstLayout && wanted.height > 0 {
            contentView.scroll(to: CGPoint(x: 0, y: max(0, wanted.height - contentView.bounds.height)))
            reflectScrolledClipView(contentView)
            firstLayout = false
        }
    }
}

private func studioScroll(_ document: NSView) -> NSScrollView {
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
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        roles.reload()
        draft = roles.assignments.load(); expected = roles.assignments.snapshot
        settings = preferences; overrides = roles.agentOverrides
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
        window = w
        refreshPalette(); refreshGrid(); refreshSizes()
        errorLabel.stringValue = roles.assignments.lastError ?? ""
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
        paletteView.widthAnchor.constraint(equalToConstant: 210).isActive = true
        search.widthAnchor.constraint(equalTo: paletteView.widthAnchor).isActive = true
        paletteView.arrangedSubviews.last!.widthAnchor.constraint(equalTo: paletteView.widthAnchor).isActive = true
        let types = NSPopUpButton()
        types.addItems(withTitles: ["All agent types"] + knownTypes)
        types.selectItem(at: agentType.isEmpty ? 0 : (knownTypes.firstIndex(of: agentType) ?? -1) + 1)
        types.target = self; types.action = #selector(selectType(_:))
        let path = NSTextField(); path.placeholderString = "Repository path, such as ~/r/worktrees/project"
        path.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        let addPath = StudioButton("Add path") { [weak self, weak path] in
            guard let self, let text = path?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            guard text.hasPrefix("/") || text == "~" || text.hasPrefix("~/") else { self.errorLabel.stringValue = "Use an absolute path or ~/ path."; return }
            if !self.draft.repositories.contains(text) { self.draft.repositories.append(text) }; self.refreshGrid()
        }
        let browse = StudioButton("Choose folder…") { [weak self] in
            let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
            if picker.runModal() == .OK, let path = picker.url?.path { self?.draft.repositories.append(path); self?.refreshGrid() }
        }
        let suggestions = NSPopUpButton(); suggestions.addItems(withTitles: ["Add a live repository…"] + Array(Set(scene.agents.compactMap(\.cwd))).sorted())
        suggestions.target = self; suggestions.action = #selector(addSuggestion(_:))
        let tools = studioStack([types, StudioButton("Add role…") { [weak self] in self?.addRole() }, suggestions], vertical: false)
        let right = studioStack([tools, studioStack([path, addPath, browse], vertical: false), gridHost, details])
        gridHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        for view in [tools, gridHost, details] { view.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true }
        let all = studioStack([paletteView, right], vertical: false)
        all.alignment = .top
        right.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -222).isActive = true
        paletteView.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
        right.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
        return all
    }

    private var knownTypes: [String] { Array(Set(["claude", "codex"] + scene.agents.compactMap(\.agent) + roles.legacyRules.flatMap { $0.agent ?? [] })).sorted() }
    private var knownRoles: [String] { Array(Set(draft.roles + draft.cells.map(\.role) + roles.legacyRules.flatMap { $0.role ?? [] } + scene.agents.compactMap { roleWord($0.label) })).filter { !$0.isEmpty }.sorted() }
    private var repositories: [String] { [""] + Array(Set(draft.repositories + draft.cells.map(\.repository) + roles.legacyRules.flatMap { $0.cwd ?? [] })).filter { !$0.isEmpty }.sorted() }

    @objc private func selectType(_ sender: NSPopUpButton) { agentType = sender.indexOfSelectedItem == 0 ? "" : sender.titleOfSelectedItem!; refreshGrid() }
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

    private func refreshGrid() {
        var rows: [[NSView]] = [[studioText("Repository / role")] + ([""] + knownRoles).map { studioText($0.isEmpty ? "All roles" : $0) }]
        for repository in repositories {
            rows.append([studioText(repository.isEmpty ? "All repositories" : repository)] + ([""] + knownRoles).map { role -> NSView in
                let cell = AssignmentCell(frame: .zero, pullsDown: false)
                cell.firstIsPlaceholder = true
                let explicit = draft.cells.first { $0.repository == repository && $0.role == role && $0.agentType == agentType }
                let inherited = inheritedChoices(repository: repository, role: role)
                let title = explicit.map { name($0.pet) } ?? (inherited.count == 1 ? "↳ " + inherited[0] : "↳ Multiple choices")
                cell.addItem(withTitle: title); cell.tokens = [nil]; cell.item(at: 0)?.isEnabled = true
                cell.addItem(withTitle: "Use inherited choice"); cell.tokens.append(nil)
                for entry in entries { cell.addItem(withTitle: entry.name); cell.tokens.append(entry.token) }
                cell.allowed = Set(entries.map(\.token)); cell.selectItem(at: 0)
                cell.setAccessibilityLabel("\(repository.isEmpty ? "All repositories" : repository), \(role.isEmpty ? "All roles" : role), \(agentType.isEmpty ? "All types" : agentType): \(title)")
                cell.toolTip = explicit == nil ? "Inherited. Choose a pet or drop one here." : "Explicit assignment. Choose inherited to remove it."
                cell.widthAnchor.constraint(equalToConstant: 155).isActive = true
                cell.inspect = { [weak self] in self?.describe(repository: repository, role: role) }
                cell.choose = { [weak self] pet in
                    guard let self else { return }
                    self.draft.set(pet, repository: repository, role: role, agentType: self.agentType)
                    self.describe(repository: repository, role: role)
                    self.refreshGrid()
                }
                return cell
            })
        }
        let grid = NSGridView(views: rows); grid.rowSpacing = 10; grid.columnSpacing = 10
        grid.column(at: 0).width = 220
        let live = studioStack([studioText("Live agents: overrides last for this native session.", secondary: true)] + scene.agents.map { agent -> NSView in
            let picker = AssignmentCell(frame: .zero, pullsDown: false)
            picker.addItem(withTitle: "Use grid and rules"); picker.tokens = [nil]
            for entry in entries { picker.addItem(withTitle: entry.name); picker.tokens.append(entry.token) }
            if let key = agent.sessionKey, let token = overrides[key], let index = picker.tokens.firstIndex(where: { $0 == token }) { picker.selectItem(at: index) }
            picker.isEnabled = agent.sessionKey != nil
            picker.allowed = Set(entries.map(\.token))
            picker.choose = { [weak self] token in if let key = agent.sessionKey { self?.overrides[key] = token } }
            return studioStack([studioText("\(agent.machine) · \(agent.label ?? agent.agent ?? "Agent")\n\(agent.cwd ?? "No repository")"), picker], vertical: false)
        })
        fill(gridHost, with: studioScroll(studioStack([grid, live])))
    }

    private func name(_ token: String) -> String { entries.first { $0.token == token }?.name ?? token }

    private func inheritedChoices(repository: String, role: String) -> [String] {
        var without = draft
        without.set(nil, repository: repository, role: role, agentType: agentType)
        var names: Set<String> = []
        let paths = repository.isEmpty ? repositories.filter { !$0.isEmpty } + ["/other"] : [repository] + repositories.filter { $0.hasPrefix(repository + "/") }
        for path in paths { for type in agentType.isEmpty ? knownTypes : [agentType] { for word in role.isEmpty ? knownRoles + ["other"] : [role] {
            let agent = Agent(terminal_id: "preview", agent_status: "idle", agent: type, label: word, cwd: AssignmentStore.prefix(path, home: NSHomeDirectory()))
            if let winner = AssignmentStore.winner(for: agent, document: without, home: NSHomeDirectory()) { names.insert(name(winner.pet)) }
            else if let rule = roles.legacyRules.first(where: { $0.matches(agent, home: NSHomeDirectory()) }) { let choice = roles.resolve(rule.pet, for: agent)
                switch choice { case .builtin(let kind): names.insert(kind.title); case .custom(let id, _): names.insert(name("custom:" + id)) } }
            else { names.insert(petKind(ofType: type).title) }
        } } }
        return names.sorted()
    }

    private func describe(repository: String, role: String) {
        let rule = PetRule(role: role.isEmpty ? nil : [role], agent: agentType.isEmpty ? nil : [agentType], cwd: repository.isEmpty ? nil : [repository], pet: "")
        let affected = scene.agents.filter { rule.matches($0, home: NSHomeDirectory()) }.map { agent -> String in
            let source: String
            if let key = agent.sessionKey, let token = overrides[key] { source = "live override: " + name(token) }
            else if let cell = AssignmentStore.winner(for: agent, document: draft, home: NSHomeDirectory()) { source = "grid: " + name(cell.pet) }
            else if let index = roles.legacyRules.firstIndex(where: { $0.matches(agent, home: NSHomeDirectory()) }) { source = "Custom rule \(index + 1): " + roles.legacyRules[index].pet }
            else { source = "agent type fallback" }
            return "\(agent.machine): \(agent.label ?? agent.agent ?? "Agent") → \(source)"
        }
        details.stringValue = "Precedence: live override, longest repository prefix, exact role, exact type, then ordered Custom rules.\nAffected agents: " + (affected.isEmpty ? "None running" : affected.joined(separator: ", "))
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
        let reduced = NSButton(checkboxWithTitle: "Reduce motion", target: self, action: #selector(selectReduced(_:)))
        reduced.state = settings.reducedMotion ? .on : .off
        return studioStack([studioText("Movement mode"), modes,
            studioText("Broadway pets walk along the bottom of the selected screen. Blocked pets approach the pointer with a question bubble."),
            reduced, studioText("Attention varies between stationary custom animations. The done animation stays the same.", secondary: true)])
    }
    @objc private func selectMovement(_ sender: NSPopUpButton) { settings.movementMode = MovementMode.allCases[sender.indexOfSelectedItem] }
    @objc private func selectReduced(_ sender: NSButton) { settings.reducedMotion = sender.state == .on }

    private func reloadDraft() {
        roles.reload()
        draft = roles.assignments.load(); expected = roles.assignments.snapshot
        settings = preferences; overrides = roles.agentOverrides
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
            preferences.size = settings.size; preferences.customPetSize = settings.customPetSize
            preferences.customSizeShares = settings.customSizeShares; preferences.movementMode = settings.movementMode
            preferences.reducedMotion = settings.reducedMotion
            preferences.save()
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
