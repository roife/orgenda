import Foundation

extension WorkspaceConfiguration {
    func updating(template: Template) -> WorkspaceConfiguration {
        var result = self
        if let index = result.capture.templates.firstIndex(where: { $0.id == template.id }) {
            result.capture.templates[index] = template
        } else {
            result.capture.templates.append(template)
        }
        return result
    }

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
