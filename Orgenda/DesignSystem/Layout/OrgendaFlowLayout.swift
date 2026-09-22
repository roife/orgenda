import SwiftUI

struct OrgendaFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = layout(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let proposedWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let limit = proposedWidth ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}
