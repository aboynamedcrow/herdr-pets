import AppKit
import SpriteKit

func screenContaining(_ point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
}

func defaultArea() -> NSRect {
    let screen = screenContaining(NSEvent.mouseLocation) ?? NSScreen.main!
    return NSRect(x: screen.visibleFrame.maxX - 280, y: screen.visibleFrame.minY + 8, width: 260, height: 80)
}

// Transparent window that passes clicks through and never takes focus.
func makeOverlay(showing view: SKView) -> NSPanel {
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
    if area.width < 80 || area.height < 60 || screenContaining(NSPoint(x: area.midX, y: area.midY)) == nil { area = defaultArea() }
    let screen = screenContaining(NSPoint(x: area.midX, y: area.midY)) ?? NSScreen.main!
    let origin = screen.frame.origin
    overlay.setFrame(screen.frame, display: true)
    scene.size = screen.frame.size
    scene.screenOrigin = origin
    scene.area = area.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.walls = screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y)
    scene.wake()   // When the area changes, pets run to the new one
}

// Opened from the panel's "Set…" button. Pets follow the translucent window as it moves; closing it saves.
final class AreaEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: area, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = t("친구들이 머무를 곳", "Home area")
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
        w.level = .floating
        w.contentMinSize = NSSize(width: 80, height: 60)
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
