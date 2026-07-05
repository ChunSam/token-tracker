import Foundation

/// Decides which of several instances running under the same bundle identifier
/// should keep running.
///
/// The macOS build has no equivalent of the Windows named mutex, so a duplicate
/// launch would double the polling rate against the shared per-account Claude
/// limit. The oldest instance wins; ties (identical launch dates, or missing
/// dates) break on the lower PID, forming a strict total order so exactly one
/// instance survives even when two launch simultaneously.
public enum InstanceArbiter {
    public struct Instance: Sendable, Equatable {
        public let pid: Int32
        public let launchDate: Date?

        public init(pid: Int32, launchDate: Date?) {
            self.pid = pid
            self.launchDate = launchDate
        }
    }

    /// Returns `true` when `current` should yield (terminate) because another
    /// instance already owns the slot.
    public static func shouldYield(current: Instance, others: [Instance]) -> Bool {
        others.contains { ownsSlot($0, over: current) }
    }

    /// Is `candidate` the rightful owner over `current`? The earlier launch wins;
    /// on a tie (or a missing launch date) the lower PID wins. A dateless instance
    /// sorts as older than a dated one so the comparison stays a total order.
    private static func ownsSlot(_ candidate: Instance, over current: Instance) -> Bool {
        switch (candidate.launchDate, current.launchDate) {
        case let (candidateDate?, currentDate?):
            return candidateDate == currentDate
                ? candidate.pid < current.pid
                : candidateDate < currentDate
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            return candidate.pid < current.pid
        }
    }
}
