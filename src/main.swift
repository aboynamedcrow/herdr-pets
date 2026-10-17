// Shows one pet per Herdr agent on screen. See README.md for build and run.

import AppKit
import SpriteKit

let arguments = CommandLine.arguments
let demo = arguments.contains("--demo")

PetKind.allCases.forEach { _ = Sprites.frames($0) }   // Preload images. Stops right here if an asset is broken

if arguments.contains("--self-test") { selfTest(); exit(0) }
if let i = arguments.firstIndex(of: "--export-frames"), i + 1 < arguments.count {
    try exportFrames(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)   // No Dock icon, never takes focus

var area = savedArea() ?? defaultArea()   // Crowd area (screen coordinates)
let scene = PetScene(size: CGSize(width: 1, height: 1))
scene.backgroundColor = .clear
scene.scaleMode = .resizeFill
let skView = SKView()
skView.allowsTransparency = true
skView.autoresizingMask = [.width, .height]
skView.presentScene(scene)
let overlay = makeOverlay(showing: skView)
let areaEditor = AreaEditor()
let controls = Controls()

layout()
if preferences.visible { overlay.orderFrontRegardless() }
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in layout() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in scene.wake() }   // macOS Reduce Motion
controls.install()
if arguments.contains("--edit") { areaEditor.show() }
if arguments.contains("--settings") { DispatchQueue.main.async { controls.show() } }

// Skip while a read is in flight.
var polling = false
func poll() {
    guard !polling else { return }
    polling = true
    DispatchQueue.global().async {
        let agents = demo ? demoAgents() : fetchAgents()
        DispatchQueue.main.async {
            polling = false
            if let agents { scene.apply(agents) }   // Keep the previous state if the read fails
            controls.refresh(connected: agents != nil)
        }
    }
}
poll()
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in poll() }
NSApplication.shared.run()
