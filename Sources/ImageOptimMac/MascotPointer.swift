import Observation
import SwiftUI

/// Window-local pointer state, observed only by the mascot artwork.
@MainActor @Observable final class MascotPointer {
    var location: CGPoint?
    var frame: CGRect = .zero

    var eyeOffset: CGSize? {
        guard let location, frame.width > 0, frame.height > 0 else { return nil }
        let dx = location.x - (frame.minX + frame.width * 0.66)
        let dy = location.y - (frame.minY + frame.height * 0.575)
        let distance = max(180, hypot(dx, dy))
        // The logo's eyes start on the right: looking left needs more travel.
        let horizontal = dx / distance * (dx < 0 ? 9 : 2.5)
        return CGSize(width: horizontal, height: dy / distance * 2)
    }
}

extension EnvironmentValues {
    @Entry var mascotPointer: MascotPointer? = nil
}
