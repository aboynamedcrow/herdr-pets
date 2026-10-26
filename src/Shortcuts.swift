import AppKit
import Carbon.HIToolbox

// Quick settings. The menu panel, Studio, and global shortcuts all change them at once, with no Apply step.

func setVisible(_ on: Bool) {
    preferences.visible = on
    preferences.save()
    scene.apply(scene.agents)
    if on { overlay.orderFrontRegardless(); scene.wake() } else { overlay.orderOut(nil); scene.stop() }
    settingsChanged()
}

func setMovement(_ mode: MovementMode) {
    preferences.movementMode = mode
    preferences.save()
    scene.wake()
    settingsChanged()
}

func setBubbles(_ on: Bool) {
    preferences.showQuestionBubbles = on
    preferences.save()
    scene.apply(scene.agents)   // Starts or stops the question reader
    settingsChanged()
}

func setCluster(_ mode: ClusterMode) {
    preferences.clusterMode = mode
    preferences.save()
    scene.apply(scene.agents)
    scene.wake()
    settingsChanged()
}

func setReducedMotion(_ on: Bool) {
    preferences.reducedMotion = on
    preferences.save()
    scene.wake()
    settingsChanged()
}

// Saves the combination, takes it from any other action, and registers all shortcuts again.
// Returns false when macOS or another app already holds the combination.
@discardableResult
func setShortcut(_ action: ShortcutAction, _ shortcut: Shortcut?) -> Bool {
    if let shortcut { preferences.shortcuts = preferences.shortcuts.filter { $0.value != shortcut } }
    preferences.shortcuts[action.rawValue] = shortcut
    preferences.save()
    hotkeys.register()
    settingsChanged()
    return !hotkeys.failed.contains(action)
}

// Moves the home area to the next monitor at the same place: the same offsets and the same flush edges.
func moveToNextScreen() {
    let screens = NSScreen.screens
    guard screens.count > 1, let current = screenContaining(NSPoint(x: area.midX, y: area.midY)), let index = screens.firstIndex(of: current) else { return }
    let next = screens[(index + 1) % screens.count]
    let placement = ScreenArea(area, in: current.visibleFrame)
    preferences.selectScreen(next.placementID, placement: placement)
    preferences.save()
    layout(on: next, placement: placement)
    areaEditor.match()
    settingsChanged()
}

// Shows the new values in open panels.
func settingsChanged() {
    controls.sync()
    petStudio.syncBehavior()
}

extension ShortcutAction {
    func perform() {
        switch self {
        case .togglePets: setVisible(!preferences.visible)
        case .toggleBubbles: setBubbles(!preferences.showQuestionBubbles)
        case .toggleMovement: setMovement(preferences.movementMode == .home ? .broadway : .home)
        case .toggleHomeArea: areaEditor.toggle()
        case .nextMonitor: moveToNextScreen()
        }
    }
}

// Carbon hot keys need no Accessibility permission. A Karabiner hyper key arrives as ⌃⌥⇧⌘ plus the key.
final class Hotkeys {
    private var registered: [EventHotKeyRef] = []
    private(set) var failed: Set<ShortcutAction> = []

    func install() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if ShortcutAction.allCases.indices.contains(Int(id.id)) { ShortcutAction.allCases[Int(id.id)].perform() }
            return noErr
        }, 1, &pressed, nil, nil)
        register()
    }

    func register() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        failed = []
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = preferences.shortcuts[action.rawValue] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5045_5453), id: UInt32(index))   // "PETS"
            if RegisterEventHotKey(shortcut.keyCode, carbonModifiers(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                registered.append(ref)
            } else { failed.insert(action) }
        }
    }

    private func carbonModifiers(_ raw: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        return [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
            .filter { flags.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
    }
}

private let namedKeys: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
]
private let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

// A key press becomes a shortcut when it has a modifier, or when it is a function key. Escape cancels.
func shortcut(from event: NSEvent) -> Shortcut? {
    let code = Int(event.keyCode)
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let function = functionKeys.firstIndex(of: code).map { "F\($0 + 1)" }
    guard code != kVK_Escape, !modifiers.isEmpty || function != nil else { return nil }
    let key = function ?? namedKeys[code] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "#\(code)"
    return Shortcut(keyCode: UInt32(code), modifiers: modifiers.rawValue, key: key)
}
