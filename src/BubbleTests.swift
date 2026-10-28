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
    IC-1834 result check. You kept group DMs with allowlisted people unrestricted.
    A side effect: in Omar's task in a group DM with Micah, a read of Omar's own
    mail or Drive posts its result where Micah can read it. Which rule should hold
    an origin post?

    ❯ 1. Hold read results
    When the audience holds another human besides the owner, ingwon and the bot,
    hold an origin post that follows a task-act read. The read result goes to
    ingwon's mirror only. Plain replies still post. Medium size.
    2. Only on audience growth
    """
    let preview = attentionQuestionPreview(sample)
    precondition(preview.hasPrefix("A side effect: in Omar's task") && preview.contains("own mail or Drive") && preview.hasSuffix("an origin post?"),
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
}
