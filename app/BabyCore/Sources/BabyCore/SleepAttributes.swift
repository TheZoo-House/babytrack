#if os(iOS)
    import ActivityKit
    import Foundation

    public struct SleepAttributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            public var startedAt: Double
            public var ended: Bool
            public init(startedAt: Double, ended: Bool = false) {
                self.startedAt = startedAt; self.ended = ended
            }
        }

        public var sessionID: String
        public var childID: String
        public var childName: String
        public init(sessionID: String, childID: String, childName: String) {
            self.sessionID = sessionID; self.childID = childID; self.childName = childName
        }
    }
#endif
