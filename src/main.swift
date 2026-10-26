// Shows one pet per Herdr agent on screen. See README.md for build and run.

import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--check-library") {
    let library = RolePets()
    library.reload()
    print("Library: " + RolePets.directory.path)
    print("Custom pets: " + library.customIDs.joined(separator: ", "))
    let missing = Set(arguments.dropFirst(index + 1)).subtracting(library.customIDs)
    if !missing.isEmpty {
        FileHandle.standardError.write(Data(("Missing custom pets: " + missing.sorted().joined(separator: ", ") + "\n").utf8))
        exit(1)
    }
    exit(0)
}
let demo = arguments.contains("--demo") || arguments.contains("--broadway-demo")
if arguments.contains("--broadway-demo") { preferences.movementMode = .broadway; preferences.showQuestionBubbles = true }
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

var area = CGRect.zero   // Crowd area currently shown (screen coordinates). Saved per monitor in preferences
let petView = NSView()
petView.wantsLayer = true
petView.autoresizingMask = [.width, .height]
let rolePets = RolePets()
rolePets.refresh()
let scene = PetScene(root: petView.layer!, roles: rolePets)
let overlay = makeOverlay(showing: petView)
let areaEditor = AreaEditor()
let controls = Controls()
let petStudio = PetStudio(roles: rolePets)

restoreArea()
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    restoreArea()
    controls.refreshScreens()
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in scene.wake() }   // macOS Reduce Motion
controls.install()
if let i = arguments.firstIndex(of: "--studio-preview"), i + 1 < arguments.count {
    scene.apply(demoAgents())
    petStudio.show()
    DispatchQueue.main.async {
        do { try petStudio.exportPreviews(to: URL(fileURLWithPath: arguments[i + 1])) }
        catch { FileHandle.standardError.write(Data("Studio preview failed: \(error)\n".utf8)); exit(1) }
        exit(0)
    }
}
if arguments.contains("--studio") { petStudio.show() }
if let i = arguments.firstIndex(of: "--stage-preview"), i + 1 < arguments.count {
    scene.apply(demoAgents())
    DispatchQueue.main.async {
        scene.apply(demoAgents())
        do { try scene.exportPreview(to: URL(fileURLWithPath: arguments[i + 1])) }
        catch { FileHandle.standardError.write(Data("Stage preview failed: \(error)\n".utf8)); exit(1) }
        exit(0)
    }
}

let agentPoller = AgentPoller(launchedByPlugin: launchedByPlugin, readAgents: { machine, complete in
    DispatchQueue.global().async {
        let agents = demo ? demoAgents() : fetchAgents(machine: machine)
        DispatchQueue.main.async { complete(agents) }
    }
}) { agents, connected, shouldExit in
    if shouldExit { exit(0) }
    scene.apply(agents)
    controls.refresh(connected: connected)
}
func poll() { agentPoller.tick(otherMachines: preferences.otherMachines && !demo) }
poll()
Timer.scheduledTimer(withTimeInterval: localPollInterval, repeats: true) { _ in poll() }
NSApplication.shared.run()
