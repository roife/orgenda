import XCTest
@testable import Orgenda

final class DocumentOutlineFilterTests: XCTestCase {
    private func node(
        _ title: String,
        state: OrgWorkflowState? = nil,
        scheduled: Date? = nil,
        deadline: Date? = nil,
        children: [DocumentOutlineNode] = []
    ) -> DocumentOutlineNode {
        DocumentOutlineNode(
            id: "\(title)-\(UUID().uuidString)",
            startByte: 0,
            title: title,
            level: 1,
            children: children,
            state: state,
            scheduled: scheduled,
            deadline: deadline
        )
    }

    private func day(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    func testInactiveFilterReturnsEverything() {
        let nodes = [node("A", state: .todo), node("B")]
        let filter = DocumentOutlineFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: nodes).map(\.title), ["A", "B"])
        XCTAssertEqual(filter.matchCount(in: nodes), 2)
    }

    func testStateFilterDropsNonMatchingHeadings() {
        var filter = DocumentOutlineFilter()
        filter.states = [.todo]
        let nodes = [node("Todo", state: .todo), node("Next", state: .next), node("Plain")]
        XCTAssertEqual(filter.apply(to: nodes).map(\.title), ["Todo"])
        XCTAssertEqual(filter.matchCount(in: nodes), 1)
    }

    func testScheduledRangeMatchesOnlyDatedHeadingsInsideRange() {
        var filter = DocumentOutlineFilter()
        filter.scheduledFrom = day("2019-05-19")
        filter.scheduledTo = day("2019-05-21")
        let nodes = [
            node("Before", state: .todo, scheduled: day("2019-05-18")),
            node("Inside", state: .todo, scheduled: day("2019-05-20")),
            node("After", state: .todo, scheduled: day("2019-05-22")),
            node("Undated", state: .todo)
        ]
        XCTAssertEqual(filter.apply(to: nodes).map(\.title), ["Inside"])
    }

    func testDeadlineUpperBoundSelectsDueItems() {
        var filter = DocumentOutlineFilter()
        filter.deadlineTo = day("2019-05-20")
        let nodes = [
            node("Overdue", state: .todo, deadline: day("2019-05-19")),
            node("OnLimit", state: .todo, deadline: day("2019-05-20")),
            node("Future", state: .todo, deadline: day("2019-05-21"))
        ]
        XCTAssertEqual(filter.apply(to: nodes).map(\.title), ["Overdue", "OnLimit"])
    }

    func testAncestorsOfMatchesAreRetainedWithFilteredChildren() {
        var filter = DocumentOutlineFilter()
        filter.states = [.todo]
        let nodes = [
            node("Parent", children: [
                node("Child Todo", state: .todo),
                node("Child Done", state: .done)
            ]),
            node("Unrelated", state: .next)
        ]
        let filtered = filter.apply(to: nodes)
        XCTAssertEqual(filtered.map(\.title), ["Parent"])
        XCTAssertEqual(filtered.first?.children.map(\.title), ["Child Todo"])
        XCTAssertEqual(filter.matchCount(in: nodes), 1)
    }

    func testCriteriaCombineWithAnd() {
        var filter = DocumentOutlineFilter()
        filter.states = [.todo]
        filter.deadlineFrom = day("2019-05-19")
        let nodes = [
            node("Both", state: .todo, deadline: day("2019-05-20")),
            node("OnlyState", state: .todo),
            node("OnlyDate", state: .done, deadline: day("2019-05-20"))
        ]
        XCTAssertEqual(filter.apply(to: nodes).map(\.title), ["Both"])
    }

    func testResetClearsEveryCriterion() {
        var filter = DocumentOutlineFilter()
        filter.states = [.todo]
        filter.scheduledFrom = day("2019-05-19")
        filter.deadlineTo = day("2019-05-20")
        XCTAssertTrue(filter.isActive)
        filter.reset()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter, DocumentOutlineFilter())
    }
}
