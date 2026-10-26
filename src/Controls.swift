import AppKit

final class Controls: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let gallery = NSStackView()   // Built-in and custom pets. Dim art the current mode cannot produce
    private let statusLabel = label("", size: 12, weight: .medium)
    private let characterNote = label("", size: 11, secondary: true)
    private let sizeLabel = label("", size: 12, secondary: true)
    private let screens = NSPopUpButton()
    private let customSizeLabel = label("", size: 12, secondary: true)
    private let customSize = NSStepper()
    private let maxLabel = label("", size: 12, secondary: true)
    private var screenRows: [NSView] = []   // Monitor row and its separator. Shown only with two or more screens
    private var connected = true

    func install() {
        let icon = NSImage(contentsOf: projectRoot.appendingPathComponent("assets/menubar-icon.png"))
        icon?.size = NSSize(width: 16, height: 16)
        icon?.isTemplate = true   // Tints to match light/dark menu bar
        icon?.accessibilityDescription = "herdr-pets"
        item.button?.image = icon
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        build()
    }

    // Builds the panel. Called again when the language changes.
    private func build() {
        let characters = characterControl(language: preferences.language, target: self, action: #selector(changeCharacters(_:)))
        characters.selectedSegment = CharacterMode.allCases.firstIndex(of: preferences.characterMode)!
        let quit = NSButton(title: t("종료", "Quit"), target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let content = stack([
            stack([label("herdr-pets", size: 17, weight: .semibold), label(t("기다리는 에이전트가 달려와요", "Blocked agents' pets come to you"), size: 12, secondary: true), statusLabel], spacing: 4),
            section(t("캐릭터", "Characters"), [characters, characterNote, gallery]),
            section(t("화면", "Display"), [displayCard()]),
            NSButton(title: "Open Pet Studio…", target: self, action: #selector(openStudio)),
            separator(),
            row(NSView(), quit),
        ], spacing: 16)

        let material = NSVisualEffectView()
        material.material = .popover
        pin(content, in: material, inset: 20)
        material.widthAnchor.constraint(equalToConstant: 340).isActive = true
        popover.contentViewController = NSViewController()
        popover.contentViewController!.view = material
        popover.contentSize = material.fittingSize
        refreshGallery()
        refresh(connected: connected)
    }

    private func displayCard() -> NSView {
        let visible = NSSwitch()
        visible.state = preferences.visible ? .on : .off
        visible.target = self; visible.action = #selector(changeVisible(_:))
        let machines = NSSwitch()
        machines.state = preferences.otherMachines ? .on : .off
        machines.target = self; machines.action = #selector(changeMachines(_:))
        customSize.minValue = 100; customSize.maxValue = 200; customSize.increment = 10
        customSize.integerValue = preferences.customPetSize
        customSize.target = self; customSize.action = #selector(changeCustomSize(_:))
        customSizeLabel.stringValue = "\(preferences.customPetSize)%"
        let limit = NSStepper()
        limit.minValue = 10; limit.maxValue = 60; limit.increment = 5
        limit.integerValue = maxPets
        limit.target = self; limit.action = #selector(changeMax(_:))
        maxLabel.stringValue = "\(maxPets)"
        let still = NSSwitch()
        still.state = preferences.reducedMotion ? .on : .off
        still.target = self; still.action = #selector(changeMotion(_:))
        let size = NSSlider(value: preferences.size, minValue: Preferences.sizeRange.lowerBound, maxValue: Preferences.sizeRange.upperBound, target: self, action: #selector(changeSize(_:)))
        sizeLabel.stringValue = "\(Int(preferences.size)) pt"
        let language = NSSegmentedControl(labels: ["한국어", "English"], trackingMode: .selectOne, target: self, action: #selector(changeLanguage(_:)))
        language.selectedSegment = preferences.language == "ko" ? 0 : 1
        screens.target = self; screens.action = #selector(changeScreen(_:))
        screenRows = [row(label(t("모니터", "Monitor"), size: 13), screens), separator()]

        let rows = stack([
            row(label(t("최대 펫 수", "Max pets"), size: 13), row(maxLabel, limit)),
            separator(),
            row(label(t("펫 표시", "Show pets"), size: 13), visible),
            separator(),
            row(label(t("다른 머신", "Other machines"), size: 13), machines),
            separator(),
            row(label(t("커스텀 펫 크기", "Custom pet size"), size: 13), row(customSizeLabel, customSize)),
            separator(),
            stack([row(label(t("펫 크기", "Pet size"), size: 13), sizeLabel), size], spacing: 6),
            separator(),
            row(stack([label(t("동작 줄이기", "Reduce motion"), size: 13), label(t("움직이지 않고 포즈로만 알려줘요", "Shows status with poses only"), size: 11, secondary: true)], spacing: 2), still),
            separator(),
            row(label(t("모이는 곳", "Home area"), size: 13), NSButton(title: t("정하기…", "Set…"), target: self, action: #selector(editArea))),
            separator(),
        ] + screenRows + [
            row(label(t("언어", "Language"), size: 13), language),
        ], spacing: 10)
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        pin(rows, in: card, inset: 12)
        return card
    }

    func show() {
        guard let button = item.button else { return }
        build()   // Studio may have changed these settings.
        refreshScreens()   // Monitors may have been plugged in or out
        popover.contentSize = popover.contentViewController!.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func refresh(connected: Bool) {
        self.connected = connected
        let count = scene.agents.count
        let waiting = scene.agents.filter { $0.needsAttention && !$0.asleep }.count
        let asleep = scene.agents.filter(\.asleep).count
        var text = demo ? t("미리보기 · 펫 \(count)마리", "Preview · \(count) pets")
            : !connected ? t("Herdr 연결을 기다리는 중", "Waiting for Herdr")
            : count == 0 ? t("실행 중인 에이전트가 없어요", "No agents running")
            : waiting > 0 ? t("에이전트 \(count) · \(waiting)개 기다리는 중", "Agents \(count) · \(waiting) blocked")
            : t("에이전트 \(count)", "Agents \(count)")
        if asleep > 0 && !demo && connected { text += t(" · \(asleep)개는 연결 끊김", " · \(asleep) asleep") }   // Their machine stopped answering
        if count > scene.pets.count { text += t(" · \(count - scene.pets.count)개는 숨김", " · \(count - scene.pets.count) hidden") }   // Pets over the display limit
        statusLabel.stringValue = text
        statusLabel.textColor = waiting > 0 ? .systemOrange : .secondaryLabelColor
        item.button?.toolTip = text
    }

    private func refreshGallery() {
        rolePets.refresh()
        characterNote.stringValue = preferences.characterMode.note
        customSize.isEnabled = preferences.characterMode == .village || preferences.characterMode == .custom
        let possible = rolePets.possible(mode: preferences.characterMode, agents: scene.agents)
        var entries = PetKind.allCases.map { (Sprites.thumbnail($0), $0.title, possible.builtin.contains($0)) }
        entries += rolePets.customIDs.compactMap { id in
            rolePets.thumbnail(id).map { ($0.image, $0.title, possible.custom.contains(id)) }
        }
        gallery.arrangedSubviews.forEach { $0.removeFromSuperview() }
        gallery.orientation = .vertical
        gallery.spacing = 4
        for start in stride(from: 0, to: entries.count, by: 7) {
            let images = entries[start..<min(start + 7, entries.count)].map { entry -> NSView in
                let image = NSImageView(image: entry.0)
                image.imageScaling = .scaleProportionallyUpOrDown
                image.widthAnchor.constraint(equalToConstant: 32).isActive = true
                image.heightAnchor.constraint(equalToConstant: 32).isActive = true
                image.alphaValue = entry.2 ? 1 : 0.22
                image.toolTip = entry.1
                return image
            }
            let row = NSStackView(views: images)
            row.spacing = 10
            gallery.addArrangedSubview(row)
        }
    }

    func refreshScreens() {
        screens.removeAllItems()
        screens.addItems(withTitles: NSScreen.screens.map(\.localizedName))
        let current = screenContaining(NSPoint(x: area.midX, y: area.midY))
        screens.selectItem(at: NSScreen.screens.firstIndex { $0 == current } ?? 0)
        screenRows.forEach { $0.isHidden = NSScreen.screens.count < 2 }
    }

    @objc private func toggle() { popover.isShown ? popover.performClose(nil) : show() }

    // apply brings back pets whose character changed.
    @objc private func changeCharacters(_ sender: NSSegmentedControl) {
        preferences.characterMode = CharacterMode.allCases[sender.selectedSegment]
        preferences.save()
        refreshGallery()
        scene.apply(scene.agents)
    }

    @objc private func changeVisible(_ sender: NSSwitch) {
        preferences.visible = sender.state == .on
        preferences.save()
        scene.apply(scene.agents)
        if preferences.visible { overlay.orderFrontRegardless(); scene.wake() } else { overlay.orderOut(nil); scene.stop() }
    }

    @objc private func changeMachines(_ sender: NSSwitch) {
        preferences.otherMachines = sender.state == .on
        preferences.save()
        poll()
    }

    @objc private func changeCustomSize(_ sender: NSStepper) {
        preferences.customPetSize = sender.integerValue
        customSizeLabel.stringValue = "\(preferences.customPetSize)%"
        preferences.save()
        scene.apply(scene.agents)
    }

    @objc private func changeMax(_ sender: NSStepper) {
        preferences.maxPets = sender.integerValue
        maxLabel.stringValue = "\(maxPets)"
        preferences.save()
        scene.apply(scene.agents)
        refresh(connected: connected)
    }

    @objc private func changeMotion(_ sender: NSSwitch) {
        preferences.reducedMotion = sender.state == .on
        preferences.save()
        scene.wake()
    }

    @objc private func changeSize(_ sender: NSSlider) {
        preferences.size = sender.doubleValue
        preferences.save()
        sizeLabel.stringValue = "\(Int(preferences.size)) pt"
        scene.wake()
    }

    @objc private func changeLanguage(_ sender: NSSegmentedControl) {
        preferences.language = sender.selectedSegment == 0 ? "ko" : "en"
        preferences.save()
        build()
    }

    @objc private func changeScreen(_ sender: NSPopUpButton) {
        guard NSScreen.screens.indices.contains(sender.indexOfSelectedItem) else { return }
        moveArea(to: NSScreen.screens[sender.indexOfSelectedItem])
    }

    @objc private func openStudio() { popover.performClose(nil); petStudio.show() }

    @objc private func editArea() {
        popover.performClose(nil)
        areaEditor.show()
    }
}

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = secondary ? .secondaryLabelColor : .labelColor
    return field
}

// Stack vertically and stretch children to the same width.
private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = spacing
    views.forEach { $0.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true }
    return s
}

// Group under a small gray title.
private func section(_ title: String, _ views: [NSView]) -> NSStackView {
    stack([label(title, size: 11, weight: .semibold, secondary: true)] + views, spacing: 8)
}

private func separator() -> NSView {
    let line = NSBox()
    line.boxType = .separator
    return line
}

private func pin(_ child: NSView, in parent: NSView, inset: CGFloat) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
}

private func row(_ left: NSView, _ right: NSView) -> NSStackView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return NSStackView(views: [left, spacer, right])
}

// The panel has 300 pt after its 20 pt margins.
func characterControl(language: String, target: AnyObject? = nil, action: Selector? = nil) -> NSSegmentedControl {
    let old = preferences.language
    preferences.language = language
    let control = NSSegmentedControl(labels: CharacterMode.allCases.map(\.title), trackingMode: .selectOne, target: target, action: action)
    preferences.language = old
    control.font = .systemFont(ofSize: 11)
    control.segmentDistribution = .fill
    return control
}
