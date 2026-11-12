import Foundation
import Observation

/// One level of the topic hierarchy, e.g. `home` in `home/livingroom/temp`.
@Observable
final class TopicNode: Identifiable {
    static let maxHistory = 300

    let segment: String
    let fullTopic: String
    weak var parent: TopicNode?

    private(set) var childrenByName: [String: TopicNode] = [:]
    private(set) var sortedChildren: [TopicNode] = []

    private(set) var lastMessage: ReceivedMessage?
    private(set) var history: [ReceivedMessage] = []
    private(set) var messageCount = 0
    /// Total number of messages received for this node and all descendants.
    private(set) var subtreeMessageCount = 0
    /// Number of topics (nodes with at least one message) in this subtree, including self.
    private(set) var subtreeTopicCount = 0

    var id: String { fullTopic }

    /// `nil` for leaves so `List(children:)` does not show a disclosure triangle.
    var childrenOrNil: [TopicNode]? { sortedChildren.isEmpty ? nil : sortedChildren }

    init(segment: String, fullTopic: String, parent: TopicNode?) {
        self.segment = segment
        self.fullTopic = fullTopic
        self.parent = parent
    }

    /// Inserts a message at the position described by its topic. Returns the leaf node.
    @discardableResult
    func insert(_ message: ReceivedMessage) -> TopicNode {
        let segments = message.topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var node = self
        var path: [TopicNode] = [self]
        for segment in segments {
            node = node.child(named: segment)
            path.append(node)
        }
        let isNewTopic = node.lastMessage == nil
        node.record(message)
        for ancestor in path {
            ancestor.subtreeMessageCount += 1
            if isNewTopic { ancestor.subtreeTopicCount += 1 }
        }
        return node
    }

    func node(forTopic topic: String) -> TopicNode? {
        var node: TopicNode? = self
        for segment in topic.split(separator: "/", omittingEmptySubsequences: false) {
            node = node?.childrenByName[String(segment)]
        }
        return node
    }

    func removeAll() {
        childrenByName = [:]
        sortedChildren = []
        lastMessage = nil
        history = []
        messageCount = 0
        subtreeMessageCount = 0
        subtreeTopicCount = 0
    }

    /// All nodes of this subtree (including self) in depth-first order.
    var allNodes: [TopicNode] {
        [self] + sortedChildren.flatMap(\.allNodes)
    }

    /// Topics in this subtree whose latest message is retained (and not already cleared).
    var retainedTopics: [String] {
        allNodes.compactMap { node in
            guard let message = node.lastMessage, message.retained, !message.payload.isEmpty else { return nil }
            return node.fullTopic
        }
    }

    /// Every stored message of this subtree, oldest first.
    var allMessages: [ReceivedMessage] {
        allNodes.flatMap(\.history).sorted { $0.receivedAt < $1.receivedAt }
    }

    private func child(named name: String) -> TopicNode {
        if let existing = childrenByName[name] { return existing }
        let topic = parent == nil && fullTopic.isEmpty ? name : "\(fullTopic)/\(name)"
        let child = TopicNode(segment: name, fullTopic: topic, parent: self)
        childrenByName[name] = child
        let index = sortedChildren.firstIndex {
            $0.segment.localizedStandardCompare(name) == .orderedDescending
        } ?? sortedChildren.endIndex
        sortedChildren.insert(child, at: index)
        return child
    }

    private func record(_ message: ReceivedMessage) {
        lastMessage = message
        messageCount += 1
        history.insert(message, at: 0)
        if history.count > Self.maxHistory {
            history.removeLast(history.count - Self.maxHistory)
        }
    }
}
