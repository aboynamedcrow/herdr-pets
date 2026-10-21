import AppKit

func screenContaining(_ point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
}

let minAreaSize = NSSize(width: 80, height: 24)

extension NSScreen {
    // Stays the same across reconnects and rearrangement, unlike the screen's index or frame.
    var placementID: String {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return "\(number)" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

// Shows the area on the most recently selected monitor that is still connected. Does not change the saved choice.
func restoreArea() {
    guard let fallback = NSScreen.screens.first else {
        overlay.orderOut(nil)
        scene.stop()
        return
    }
    let id = preferences.preferredScreen(in: NSScreen.screens.map(\.placementID))
    let screen = NSScreen.screens.first { $0.placementID == id } ?? fallback
    layout(on: screen, placement: preferences.screenAreas[screen.placementID] ?? .standard)
    if preferences.visible { overlay.orderFrontRegardless() }
}

// Transparent window that passes clicks through and never takes focus.
func makeOverlay(showing view: NSView) -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.contentView = view
    return panel
}

// Shows the area on the given screen without saving it.
func layout(on screen: NSScreen, placement: ScreenArea) {
    area = placement.rect(in: screen.visibleFrame)
    let origin = screen.frame.origin
    overlay.setFrame(screen.frame, display: true)
    scene.screenOrigin = origin
    scene.area = area.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.walls = screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.wake()   // When the area changes, pets run to the new one
}

// Picking a monitor makes it the first choice. A monitor without a saved spot gets the same spot as the current one.
func moveArea(to screen: NSScreen) {
    let id = screen.placementID
    let from = screenContaining(NSPoint(x: area.midX, y: area.midY))?.visibleFrame ?? screen.visibleFrame
    let placement = preferences.screenAreas[id] ?? ScreenArea(area, in: from)
    preferences.selectScreen(id, placement: placement)
    preferences.save()
    layout(on: screen, placement: placement)
}

// Opened from the panel's "Set…" button. Pets follow the translucent window as it moves; closing it saves.
final class AreaEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: area, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = t("친구들이 머무를 곳", "Home area")
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
        w.level = .floating
        w.contentMinSize = minAreaSize
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private func follow(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        let rect = w.contentRect(forFrameRect: w.frame)
        guard let screen = screenContaining(NSPoint(x: rect.midX, y: rect.midY)) ?? w.screen else { return }
        layout(on: screen, placement: ScreenArea(rect, in: screen.visibleFrame))
    }
    func windowDidMove(_ n: Notification) { follow(n) }
    func windowDidResize(_ n: Notification) { follow(n) }
    func windowWillClose(_ n: Notification) {
        follow(n)
        if let screen = screenContaining(NSPoint(x: area.midX, y: area.midY)) {
            preferences.selectScreen(screen.placementID, placement: ScreenArea(area, in: screen.visibleFrame))
            preferences.save()
        }
        window = nil
    }
}
