import AppKit

func bubbleSelfTest() {
    let pointer = CGPoint(x: 140, y: 320)
    let distant = CGRect(x: 300, y: 300, width: 100, height: 60)
    let arrived = CGRect(x: 100, y: 300, width: 100, height: 60)
    precondition(!bubblePointerState(frame: distant, pointer: pointer).inside)
    precondition(bubblePointerState(frame: arrived, pointer: pointer).inside,
                 "A bubble that moves under a fixed pointer enters hover")
    for offset: CGFloat in [0, 23] {
        let state = bubblePointerState(frame: arrived, pointer: CGPoint(x: arrived.minX - offset, y: arrived.midY), previousPointer: pointer)
        precondition(state.holds, "The bubble holds inside its frame and 24 pt margin")
    }
    precondition(!bubblePointerState(frame: arrived, pointer: CGPoint(x: arrived.minX - 25, y: arrived.midY)).holds,
                 "The bubble releases outside the margin")
    precondition(!bubblePointerState(frame: arrived, pointer: CGPoint(x: arrived.minX - 1, y: arrived.midY)).inside,
                 "The hold margin does not expand the bubble")
    let near = CGPoint(x: arrived.minX - 12, y: arrived.midY)
    precondition(!bubblePointerState(frame: arrived, pointer: near, previousPointer: near).holds,
                 "A still pointer outside the frame does not stop an approaching bubble")
    precondition(!bubblePointerState(frame: arrived, pointer: near).holds,
                 "The first layout does not assume pointer movement")
    precondition(bubblePointerState(frame: arrived, pointer: pointer, previousPointer: pointer).holds,
                 "A still pointer inside the frame holds the bubble")
    var approaching = CGRect(x: 200, y: 300, width: 60, height: 60)
    for _ in 0..<6 {
        precondition(!bubblePointerState(frame: approaching, pointer: pointer, previousPointer: pointer).holds,
                     "A moving bubble crosses the margin beneath a still pointer")
        approaching.origin.x -= 10
    }
    precondition(bubblePointerState(frame: approaching, pointer: pointer, previousPointer: pointer).inside,
                 "The approaching bubble reaches the still pointer")
    print("PASS: Bubble hold requires pointer entry or movement within the margin, and permits stationary-pointer arrival")

    let band = CGRect(x: 0, y: 0, width: 500, height: 40)
    let pet = Pet(id: "hold", kind: .codex, spot: CGPoint(x: 0.5, y: 0.5), in: band)
    pet.setStatus("blocked")
    let world = World(band: band, path: Perimeter(r: CGRect(x: 0, y: 0, width: 500, height: 700)),
                      cursor: CGPoint(x: 200, y: 0), scale: 1, still: true)
    _ = pet.step(t: 0, dt: 0, world: world)
    let initial = pet.position
    pet.holdsBubble = true
    let movedPointer = World(band: band, path: world.path, cursor: CGPoint(x: 500, y: 500), scale: 1, still: true)
    _ = pet.step(t: 1, dt: 0, world: movedPointer)
    precondition(pet.position == initial, "A blocked pet stays in place during the hold")
    pet.holdsBubble = false
    _ = pet.step(t: 2, dt: 0, world: movedPointer)
    precondition(pet.position != initial, "A blocked pet retargets after the hold")
    print("PASS: Reduce Motion pets stop during the bubble hold and retarget after release")
    movingBubbleHoldSelfTest()

    var agent = Agent(terminal_id: "bubble", agent_status: "blocked", agent: "claude", label: "GLE IC-1834 Orchestrator task")
    precondition(compactBubbleTitle(agent: agent) == "IC-1834 · Orchestrator", "Short header: local identity")
    agent.machine = "ce447e49d7ef4c9eab6291e931074360"
    let machines = try! JSONDecoder().decode([Machine].self, from: Data("""
    [{"id":"ce447e49d7ef4c9eab6291e931074360","enabled":true,"target":"megatron"},
     {"id":"old-remote","enabled":true}]
    """.utf8))
    let poller = AgentPoller(launchedByPlugin: false, readAgents: { _, done in done([]) },
                             readMachines: { done in done(machines) }, onUpdate: { _, _, _ in })
    poller.tick(otherMachines: true)
    precondition(compactBubbleTitle(agent: agent, machineName: poller.machineNames[agent.machine]) == "IC-1834 · Orchestrator · megatron",
                 "Short header: remote target reaches the bubble")
    agent.machine = "old-remote"
    precondition(compactBubbleTitle(agent: agent, machineName: poller.machineNames[agent.machine]) == "IC-1834 · Orchestrator",
                 "Short header: remote without target omits the machine")
    agent.label = nil
    precondition(compactBubbleTitle(agent: agent) == "claude", "Short header: no label uses the agent name")
    agent.label = "A label without an issue or role"
    precondition(compactBubbleTitle(agent: agent) == agent.label, "Short header: other labels remain available for tail truncation")
    print("PASS: Short headers use local identity, remote targets, missing targets, and agent names")

    let sample = """
    The sample garden has a row of blue flowers beside a small stone path.
    A display choice: the next preview can show every flower beside the winding
    path or keep the smaller view with a single row and a short legend. Which view should appear
    in the next preview?

    ❯ 1. Show every flower
    Use the wider view with all flowers and the complete path.
    keep the legend below the picture so the colors remain easy to compare.
    2. Keep the small view
    """
    let preview = attentionQuestionPreview(sample)
    precondition(preview.hasPrefix("A display choice: the next preview") && preview.contains("winding path") && preview.hasSuffix("in the next preview?"),
                 "First-line preview keeps the paragraph start beyond 180 characters")
    precondition(attentionQuestionPreview("").isEmpty, "No question text gives no preview filler")
    let joined = joinedQuestionLines("A wrapped sentence\ncontinues here.\n\nkeep a new paragraph.\n❯ 1. Choose\nmore detail\n2. Keep\n• bullet\n⏺ turn\n› input\n❯ prompt\nUppercase start")
    precondition(joined.contains("sentence continues here.") && joined.contains("\n\nkeep a new paragraph."), "Readable body joins lowercase continuations and keeps empty lines")
    precondition(joined.contains("❯ 1. Choose\nmore detail"), "Readable body keeps an option separate from its explanation")
    for line in ["❯ 1. Choose", "2. Keep", "• bullet", "⏺ turn", "› input", "❯ prompt", "Uppercase start"] {
        precondition(joined.contains("\n" + line), "Readable body keeps option, marker, and uppercase starts")
    }
    print("PASS: First-line preview keeps its start and body text joins terminal wraps")

    let screen = CGRect(x: 100, y: 200, width: 500, height: 700)
    let title = "IC-1834 · Orchestrator"
    let empty = questionBubbleSize(text: "", title: title, expanded: false, screen: screen.size)
    let collapsed = questionBubbleSize(text: sample, title: title, expanded: false, screen: screen.size)
    let expanded = questionBubbleSize(text: sample, title: title, expanded: true, screen: screen.size)
    precondition(empty.height < collapsed.height && collapsed.height < expanded.height, "Sizes separate identity, preview, and body")
    let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    let headerSize = (title as NSString).size(withAttributes: [.font: headerFont])
    precondition(empty.width > headerSize.width && empty.height > headerSize.height,
                 "Identity bubbles fit the 12 pt header")
    let short = questionBubbleSize(text: "Apply?", title: title, expanded: true, screen: screen.size)
    let button = NSButton(title: "Open agent", target: nil, action: nil)
    button.bezelStyle = .rounded
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { button.bezelStyle = .glass }
    #endif
    let bodySize = ("Apply?" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
    precondition(short.height > headerSize.height + bodySize.height + button.fittingSize.height,
                 "Expanded bubbles fit the header, body, and native button")
    for x in [screen.minX + 6, screen.maxX - collapsed.width - 6] {
        for y in [screen.minY + 6, screen.maxY - collapsed.height - 6] {
            let anchor = CGRect(origin: CGPoint(x: x, y: y), size: collapsed)
            let rect = expandedBubbleRect(from: anchor, size: expanded, screen: screen)
            precondition(rect.contains(anchor) && screen.contains(rect), "Hover expansion retains the collapsed panel and clamps each screen corner")
        }
    }
    print("PASS: Bubble sizes fit the new text and expansion retains the anchor within the screen")

    let anchor = CGRect(x: 150, y: 700, width: 260, height: 54)
    let large = expandedBubbleRect(from: anchor, size: CGSize(width: 460, height: 420), screen: screen)
    let resizePointer = CGPoint(x: large.maxX - 12, y: large.minY + 12)
    let small = expandedBubbleRect(from: anchor, size: CGSize(width: 230, height: 98), screen: screen,
                                   previous: large, pointer: resizePointer)
    precondition(small.width < large.width && small.height < large.height,
                 "Expanded size shrinks after shorter text arrives")
    precondition(small.width >= anchor.width && small.height >= anchor.height,
                 "Expanded size uses the collapsed frame as its minimum")
    precondition(small.contains(resizePointer) && screen.contains(small),
                 "Expanded shrink keeps the pointer inside the panel and clamps the screen")
    let repeated = expandedBubbleRect(from: anchor, size: CGSize(width: 230, height: 98), screen: screen,
                                      previous: small, pointer: resizePointer)
    precondition(repeated == small, "Expanded shrink settles without moving on the next update")
    print("PASS: Expanded bubbles shrink from the collapsed minimum while retaining the pointer")

    precondition(bubbleClickTarget(inside: true, expanded: false, overText: true, overControl: false) == .openAgent,
                 "Click target: collapsed bubbles open the agent")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: false, overControl: false) == .openAgent,
                 "Click target: expanded headers and glass padding open the agent")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: true, overControl: false) == .textSelection,
                 "Click target: body text keeps native selection")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: false, overControl: true) == .control,
                 "Click target: Open buttons and scrollers keep their actions")
    precondition(bubbleClickTarget(inside: false, expanded: true, overText: false, overControl: false) == .none,
                 "Click target: outside clicks pass through")
    print("PASS: Bubble clicks open from the surface and preserve body selection and controls")
}


private func movingBubbleHoldSelfTest() {
    func require(_ condition: @autoclosure () -> Bool, _ message: String = "A bubble hold check failed") {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let path = Perimeter(r: screen.insetBy(dx: 40, dy: 40))
    let dt: CGFloat = 1 / 30
    for startY: CGFloat in [40, 300] {
        let band = CGRect(x: 400, y: startY, width: 200, height: 0)
        let pet = Pet(id: "moving-hold", kind: .codex, spot: CGPoint(x: 0.5, y: 0), in: band)
        pet.setStatus("blocked")
        let towardRight = World(band: band, path: path, cursor: CGPoint(x: 900, y: 40), scale: 1, still: false)
        for tick in 0...18 { _ = pet.step(t: Double(tick) / 30, dt: dt, world: towardRight) }
        require(pet.isDashing, "The hold starts during a run")
        let stopped = pet.position, rotation = pet.zRotation
        let body = pet.layer.sublayers!.first!, sprite = body.sublayers!.first!
        let pose = sprite.contents as AnyObject?, facing = body.affineTransform(), bounce = body.position
        let head = pet.badge.position
        let towardLeft = World(band: band, path: path, cursor: CGPoint(x: 100, y: 40), scale: 1, still: false)
        pet.holdsBubble = true
        for tick in 19...30 {
            require(pet.step(t: Double(tick) / 30, dt: dt, world: towardLeft), "Held pets keep scene ticks for release")
            require(pet.position == stopped && pet.zRotation == rotation && !pet.isDashing,
                         "A held pet keeps its position and angle")
            require(sprite.contents as AnyObject? === pose && body.affineTransform() == facing && body.position == bounce,
                         "A held pet keeps its sprite, facing, and bounce")
            require(pet.badge.position == head, "The head stays below the held bubble")
        }

        if startY == 40 {
            var pointer = CGPoint(x: -1000, y: -1000)
            let bubbles = SpeechBubbles(pointerLocation: { pointer })
            defer { bubbles.hideAll() }
            let agent = Agent(terminal_id: "held-frame", agent_status: "blocked", agent: "codex")
            func layout() { bubbles.update(agents: [agent], pets: [agent.id: pet], texts: [:], origin: .zero, screen: screen) }
            layout()
            let heldFrame = bubbles.frame(for: agent.id)!
            pointer = CGPoint(x: heldFrame.minX - 12, y: heldFrame.midY)
            require(bubbles.holdsPet(agent.id, pointer: pointer), "Pointer movement within 24 pt holds the pet")
            layout()
            // A text arrival or poll can lay out again before the next scene tick.
            layout()
            require(bubbles.frame(for: agent.id) == heldFrame, "An extra layout above a stopped pet does not jump: \(heldFrame) -> \(String(describing: bubbles.frame(for: agent.id)))")
            pointer = CGPoint(x: -1000, y: -1000)
            pet.holdsBubble = bubbles.holdsPet(agent.id, pointer: pointer)
            require(!pet.holdsBubble)
            layout()
            // Compare native frames because AppKit rounds panel origins to whole points.
            let aboveHeadBubbles = SpeechBubbles(pointerLocation: { CGPoint(x: -1000, y: -1000) })
            defer { aboveHeadBubbles.hideAll() }
            aboveHeadBubbles.update(agents: [agent], pets: [agent.id: pet], texts: [:], origin: .zero, screen: screen)
            let aboveHead = aboveHeadBubbles.frame(for: agent.id)!
            require(bubbles.frame(for: agent.id) == heldFrame && heldFrame == aboveHead,
                         "Release keeps the bubble above the stopped head: \(heldFrame), \(aboveHead), \(String(describing: bubbles.frame(for: agent.id)))")
        }

        pet.holdsBubble = false
        _ = pet.step(t: 31.0 / 30, dt: dt, world: towardLeft)
        let distance = hypot(pet.position.x - stopped.x, pet.position.y - stopped.y)
        require(pet.isDashing && distance > 0 && distance <= acceleration * dt * dt + 0.001,
                     "Release accelerates from rest without a jump")
        if startY == 40 { require(pet.position.x < stopped.x, "Release chooses the pointer goal instead of the old goal") }
        else { require(pet.position.y < stopped.y, "Release resumes the edge approach") }
    }
    print("PASS: Moving pets hold their pose and position, release without a bubble jump, and accelerate toward the pointer")

    let band = CGRect(x: 400, y: 300, width: 200, height: 0)
    let pet = Pet(id: "hop-hold", kind: .codex, spot: CGPoint(x: 0.5, y: 0), in: band)
    pet.setStatus("blocked")
    pet.holdsBubble = true
    let world = World(band: band, path: path, cursor: CGPoint(x: 900, y: 40), scale: 1, still: false)
    let initial = pet.position
    _ = pet.step(t: 0, dt: dt, world: world)
    _ = pet.step(t: 0.175, dt: dt, world: world)
    require(pet.layer.sublayers!.first!.position.y > 0, "The startled hop plays during a hold")
    _ = pet.step(t: 0.35, dt: dt, world: world)
    require(pet.position == initial && pet.layer.sublayers!.first!.position.y == 0 && !pet.isDashing,
                 "The hold takes effect after the startled hop lands")
    print("PASS: A bubble hold lets the startled hop finish before the pet stops")
}
