// Shows one pet per Herdr agent on screen. See README.md for build and run.

import AppKit
import SpriteKit

let arguments = CommandLine.arguments
let demo = arguments.contains("--demo")
let launchedByPlugin = ProcessInfo.processInfo.environment["HERDR_PLUGIN_ID"] != nil

if arguments.contains("--self-test") { selfTest(); exit(0) }
if let i = arguments.firstIndex(of: "--export-frames"), i + 1 < arguments.count {
    try exportFrames(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}

// One instance only (demo excepted). The plugin starts the app on every status event. The lock is released when the process exits.
// ponytail: one lock for all Herdr sessions, so only the first session gets pets. Key the lock by HERDR_SOCKET_PATH if several sessions matter.
let lock = open(FileManager.default.temporaryDirectory.appendingPathComponent("herdr-pets.lock").path, O_CREAT | O_RDWR, 0o644)
guard demo || flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

PetKind.allCases.forEach { _ = Sprites.frames($0) }   // Preload images. Stops right here if an asset is broken

NSApplication.shared.setActivationPolicy(.accessory)   // No Dock icon, never takes focus

var area = preferences.area ?? defaultArea()   // Crowd area (screen coordinates). Saved to preferences when the editor closes
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

// Skip while a read is in flight.
var polling = false
var failures = 0
func poll() {
    guard !polling else { return }
    polling = true
    DispatchQueue.global().async {
        let agents = demo ? demoAgents() : fetchAgents()
        DispatchQueue.main.async {
            polling = false
            failures = agents == nil ? failures + 1 : 0
            if launchedByPlugin && failures >= 15 { exit(0) }   // Herdr server is gone for 30 seconds

            if let agents { scene.apply(agents) }   // Keep the previous state if the read fails
            controls.refresh(connected: agents != nil)
        }
    }
}
poll()
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in poll() }
NSApplication.shared.run()
