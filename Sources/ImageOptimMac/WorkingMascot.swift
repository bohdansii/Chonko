import SwiftUI

struct WorkingMascot: View {
    enum Activity { case idle, searching, optimizing }
    private enum IdlePhase { case rest, breathe, hop, land }
    var activity: Activity = .optimizing
    @Environment(\.mascotPointer) private var pointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
                if reduceMotion {
                    MascotArtwork(animated: !reduceMotion, activity: activity)
                } else if activity == .idle {
                    MascotArtwork(animated: !reduceMotion, activity: activity)
                        .phaseAnimator([IdlePhase.rest, .breathe, .rest, .breathe, .rest, .hop, .land, .rest]) { image, phase in
                            image
                                .scaleEffect(x: phase == .land ? 1.04 : 1,
                                             y: phase == .breathe ? 1.025 : phase == .land ? 0.96 : 1,
                                             anchor: .bottom)
                                .offset(y: phase == .hop ? -5 : 0)
                        } animation: { phase in
                            switch phase {
                            case .hop: .easeOut(duration: 0.32)
                            case .land: .easeIn(duration: 0.38)
                            case .rest, .breathe: .easeInOut(duration: 1.8)
                            }
                        }
                } else {
                    MascotArtwork(animated: !reduceMotion, activity: activity)
                        .phaseAnimator([false, true]) { image, phase in
                            let direction: CGFloat = phase ? 1 : -1
                            image
                                .scaleEffect(x: 1 + direction * (activity == .optimizing ? 0.03 : 0.012),
                                             y: 1 - direction * (activity == .optimizing ? 0.04 : 0.018),
                                             anchor: .bottom)
                                .rotationEffect(.degrees(activity == .searching ? Double(direction) * 4 : 0))
                                .offset(x: activity == .searching ? direction * 2 : 0)
                        } animation: { _ in
                            .easeInOut(duration: activity == .searching ? 1 : 0.8)
                        }
                }
        }
        .frame(width: 56, height: 46)
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("mascotWorkspace"))
        } action: { frame in pointer?.frame = frame }
        .accessibilityHidden(true)
    }
}
