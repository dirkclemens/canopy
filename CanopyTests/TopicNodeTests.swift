import Foundation
import Testing
@testable import Canopy

@Suite("Topic-Baum")
struct TopicNodeTests {
    private func message(_ topic: String, _ payload: String, retained: Bool = false,
                         at date: Date = Date()) -> ReceivedMessage {
        ReceivedMessage(topic: topic, payload: Data(payload.utf8), qos: .atMostOnce,
                        retained: retained, receivedAt: date)
    }

    @Test func insertBuildsHierarchy() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        root.insert(message("home/livingroom/temp", "21.5"))
        root.insert(message("home/kitchen/temp", "19"))

        let home = try! #require(root.node(forTopic: "home"))
        #expect(home.sortedChildren.map(\.segment) == ["kitchen", "livingroom"])
        #expect(root.node(forTopic: "home/livingroom/temp")?.lastMessage?.text == "21.5")
        #expect(root.node(forTopic: "home/livingroom/temp")?.fullTopic == "home/livingroom/temp")
        #expect(home.lastMessage == nil)
        #expect(root.node(forTopic: "home/garage") == nil)
    }

    @Test func countsAreAggregated() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        root.insert(message("a/b", "1"))
        root.insert(message("a/b", "2"))
        root.insert(message("a/c", "3"))

        let a = try! #require(root.node(forTopic: "a"))
        #expect(a.subtreeMessageCount == 3)
        #expect(a.subtreeTopicCount == 2)
        #expect(root.node(forTopic: "a/b")?.messageCount == 2)
        #expect(root.node(forTopic: "a/b")?.history.map(\.text) == ["2", "1"])
    }

    @Test func emptySegmentsArePreserved() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        root.insert(message("/leading", "x"))
        #expect(root.sortedChildren.first?.segment == "")
        #expect(root.node(forTopic: "/leading")?.lastMessage?.text == "x")
    }

    @Test func historyIsCapped() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        for i in 0..<(TopicNode.maxHistory + 10) {
            root.insert(message("t", "\(i)"))
        }
        let node = try! #require(root.node(forTopic: "t"))
        #expect(node.history.count == TopicNode.maxHistory)
        #expect(node.messageCount == TopicNode.maxHistory + 10)
    }

    @Test func retainedTopicsInSubtree() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        root.insert(message("s/one", "1", retained: true))
        root.insert(message("s/two", "2", retained: false))
        root.insert(message("s/three", "", retained: true))   // already cleared
        root.insert(message("other", "x", retained: true))

        #expect(root.node(forTopic: "s")?.retainedTopics == ["s/one"])
        #expect(Set(root.retainedTopics) == ["s/one", "other"])
    }

    @Test func allMessagesSortedByDate() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        let now = Date()
        root.insert(message("b", "2", at: now.addingTimeInterval(2)))
        root.insert(message("a", "1", at: now.addingTimeInterval(1)))
        root.insert(message("a/c", "3", at: now.addingTimeInterval(3)))
        #expect(root.allMessages.map(\.text) == ["1", "2", "3"])
    }

    @Test func removeAllClearsTree() {
        let root = TopicNode(segment: "", fullTopic: "", parent: nil)
        root.insert(message("x/y", "1"))
        root.removeAll()
        #expect(root.sortedChildren.isEmpty)
        #expect(root.subtreeMessageCount == 0)
        #expect(root.node(forTopic: "x") == nil)
    }
}
