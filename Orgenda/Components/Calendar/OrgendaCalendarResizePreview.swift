import SwiftUI

struct OrgendaCalendarResizePreview<Content: View>: View, Animatable {
    var position: CGFloat
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View { content(position) }
}

#if DEBUG
import UIKit

/// Opt-in main-thread frame cadence capture for repeatable simulator runs.
/// This measures display-link callbacks, not GPU presentation or device FPS.
@MainActor
final class OrgendaCalendarFrameProbe: NSObject {
    static let shared = OrgendaCalendarFrameProbe()
    private let tag = ProcessInfo.processInfo.environment["ORGENDA_CALENDAR_PROFILE"]
    private let runID = UUID().uuidString
    private var displayLink: CADisplayLink?
    private var intervals: [Double] = []
    private var previousTime = 0.0
    private var startTime = 0.0
    private var firstFrame = 0.0
    private var targetInterval = 0.0

    func start() {
        guard tag != nil, displayLink == nil else { return }
        intervals = []
        intervals.reserveCapacity(1024)
        previousTime = 0
        firstFrame = 0
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if previousTime > 0 { intervals.append((now - previousTime) * 1000) }
        else { firstFrame = (now - startTime) * 1000 }
        previousTime = now
        targetInterval = (link.targetTimestamp - link.timestamp) * 1000
    }

    func stop() {
        guard let tag, let displayLink else { return }
        displayLink.invalidate()
        self.displayLink = nil
        let report: [String: Any] = [
            "tag": tag, "runID": runID, "intervalsMS": intervals,
            "firstFrameMS": firstFrame, "targetIntervalMS": targetInterval,
            "durationMS": (CACurrentMediaTime() - startTime) * 1000
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report) else { return }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("orgenda-calendar-frame-profile.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: data + Data([10]))
        }
    }
}
#endif
