import AppKit

func screenContaining(_ point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
}

let minAreaSize = NSSize(width: 80, height: 24)

func defaultArea() -> NSRect {
    let screen = screenContaining(NSEvent.mouseLocation) ?? NSScreen.main!
    return NSRect(x: screen.visibleFrame.maxX - 280, y: screen.visibleFrame.minY + 8, width: 260, height: 60)
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

// Fit the overlay to the screen holding the area's center. If that screen is gone (monitor unplugged) or the area is too small, move to the default area.
func layout() {
    if area.width < minAreaSize.width || area.height < minAreaSize.height || screenContaining(NSPoint(x: area.midX, y: area.midY)) == nil { area = defaultArea() }
    let screen = screenContaining(NSPoint(x: area.midX, y: area.midY)) ?? NSScreen.main!
    let origin = screen.frame.origin
    overlay.setFrame(screen.frame, display: true)
    scene.screenOrigin = origin
    scene.area = area.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.walls = screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.wake()   // When the area changes, pets run to the new one
}

// Moves the area to the same spot on another screen: same distance from the right and bottom edges, kept inside that screen.
func moveArea(to screen: NSScreen) {
    let from = (screenContaining(NSPoint(x: area.midX, y: area.midY)) ?? NSScreen.main!).visibleFrame
    let to = screen.visibleFrame
    let width = min(area.width, to.width), height = min(area.height, to.height)
    let x = min(max(to.maxX - (from.maxX - area.minX), to.minX), to.maxX - width)
    let y = min(max(to.minY + (area.minY - from.minY), to.minY), to.maxY - height)
    area = NSRect(x: x, y: y, width: width, height: height)
    preferences.area = area
    preferences.save()
    layout()
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
        area = w.contentRect(forFrameRect: w.frame)
        layout()
    }
    func windowDidMove(_ n: Notification) { follow(n) }
    func windowDidResize(_ n: Notification) { follow(n) }
    func windowWillClose(_ n: Notification) {
        follow(n)
        preferences.area = area
        preferences.save()
        window = nil
    }
}
