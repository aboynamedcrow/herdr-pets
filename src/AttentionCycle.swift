import Foundation

private struct AttentionRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

struct AttentionCycle {
    private let counts: [Pose: Int]
    private var random: AttentionRandom
    private var bag: [Pose] = []
    private var pose = Pose.blocked
    private var start: Double?
    private var end = 0.0

    init(counts: [Pose: Int], seed: UInt64) {
        let stationary: [Pose] = [.resting, .jump, .thinking, .blocked, .working, .sleeping]
        self.counts = counts.filter { stationary.contains($0.key) && $0.value > 0 }
        random = AttentionRandom(state: seed)
    }

    mutating func sample(at time: Double) -> (pose: Pose, frame: Int) {
        if start == nil || time < start! {
            start = time
            choose()
            end = time + Double(counts[pose] ?? 1) / 4
        }
        var loops = 0
        while time >= end && loops < 128 {
            start = end
            choose()
            end += Double(counts[pose] ?? 1) / 4
            loops += 1
        }
        if time >= end { start = time; end = time + Double(counts[pose] ?? 1) / 4 }
        return (pose, min((counts[pose] ?? 1) - 1, max(0, Int((time - start!) * 4))))
    }

    private mutating func choose() {
        if bag.isEmpty {
            bag = counts.keys.sorted { $0.rawValue < $1.rawValue }.shuffled(using: &random)
            if bag.count > 1 && bag.last == pose { bag.swapAt(0, bag.count - 1) }
        }
        pose = bag.popLast() ?? .blocked
    }
}
