import AppKit

func bubbleSelfTest() {
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
    let pointer = CGPoint(x: large.maxX - 12, y: large.minY + 12)
    let small = expandedBubbleRect(from: anchor, size: CGSize(width: 230, height: 98), screen: screen,
                                   previous: large, pointer: pointer)
    precondition(small.width < large.width && small.height < large.height,
                 "Expanded size shrinks after shorter text arrives")
    precondition(small.width >= anchor.width && small.height >= anchor.height,
                 "Expanded size uses the collapsed frame as its minimum")
    precondition(small.contains(pointer) && screen.contains(small),
                 "Expanded shrink keeps the pointer inside the panel and clamps the screen")
    let repeated = expandedBubbleRect(from: anchor, size: CGSize(width: 230, height: 98), screen: screen,
                                      previous: small, pointer: pointer)
    precondition(repeated == small, "Expanded shrink settles without moving on the next update")
    print("PASS: Expanded bubbles shrink from the collapsed minimum while retaining the pointer")

    precondition(bubbleClickTarget(inside: true, expanded: false, overText: true, overControl: false) == .openAgent,
                 "Click target: collapsed bubbles open the agent")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: false, overControl: false) == .openAgent,
                 "Click target: expanded headers and blue padding open the agent")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: true, overControl: false) == .textSelection,
                 "Click target: body text keeps native selection")
    precondition(bubbleClickTarget(inside: true, expanded: true, overText: false, overControl: true) == .control,
                 "Click target: Open buttons and scrollers keep their actions")
    precondition(bubbleClickTarget(inside: false, expanded: true, overText: false, overControl: false) == .none,
                 "Click target: outside clicks pass through")
    print("PASS: Bubble clicks open from the surface and preserve body selection and controls")
}
