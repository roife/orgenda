import Foundation

extension WorkspaceConfiguration {
    /// A workflow preset never changes paths, templates, reminder rules or history.
    func applyingClassicWorkflowPreset() -> WorkspaceConfiguration {
        var result = self
        result.workflow = Workflow(
            sequences: [Sequence(process: ["TODO", "NEXT", "WAIT", "SOMEDAY", "URGENT"],
                                 terminal: ["DONE", "CANCELED"])],
            keywords: [
                "WAIT": Keyword(log: StateLog(enter: .note, leave: .time)),
                "URGENT": Keyword(log: StateLog(enter: .time)),
                "DONE": Keyword(log: StateLog(enter: .time)),
                "CANCELED": Keyword(log: StateLog(enter: .note))
            ]
        )
        return result
    }
}
