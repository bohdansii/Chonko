import SwiftUI

/// The selected logo's vector paths, with the eyes separate from the body.
struct MascotArtwork: View {
    let animated: Bool
    let activity: WorkingMascot.Activity
    @Environment(\.mascotPointer) private var pointer
    private enum Gaze { case still, looking, pause, closed, reopened }

    var body: some View {
        let trackingOffset = animated && activity == .idle ? pointer?.eyeOffset : nil
        ZStack {
            if animated {
                Color.clear.phaseAnimator([-1.0, 1.0]) { _, phase in
                    skin(deformation: phase)
                } animation: { _ in
                    .easeInOut(duration: activity == .optimizing ? 1.1 : 2.8)
                }
            } else { skin(deformation: 0) }
            if activity == .optimizing {
                eyes
                    .offset(x: -4, y: -1)
                    .phaseAnimator([false, true]) { eyes, phase in
                        eyes.scaleEffect(y: phase && animated ? 0.8 : 1, anchor: UnitPoint(x: 0.66, y: 0.575))
                    } animation: { _ in animated ? .easeInOut(duration: 0.85) : nil }
            } else if animated {
                eyes.phaseAnimator([Gaze.still, .looking, .still, .pause, .closed, .reopened]) { eyes, phase in
                    eyes
                        .scaleEffect(y: phase == .closed ? 0.12 : 1, anchor: UnitPoint(x: 0.66, y: 0.575))
                        .offset(x: phase == .looking && trackingOffset == nil ? (activity == .searching ? 1.3 : 0.65) : 0)
                } animation: { phase in
                    switch phase {
                    case .closed: .easeInOut(duration: 0.12)
                    case .reopened: .easeOut(duration: 0.18)
                    case .looking: .easeInOut(duration: 1.2)
                    case .still, .pause: .easeInOut(duration: 2.4)
                    }
                }
                .offset(trackingOffset ?? .zero)
                .animation(.easeOut(duration: 0.18), value: trackingOffset)
            } else { eyes }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func skin(deformation: Double) -> some View {
        let shape = MascotBody(deformation: deformation, roundness: activity == .optimizing ? 1 : 0)
        return shape
            .fill(LinearGradient(stops: [
                .init(color: Color(red: 1, green: 0.75, blue: 0.58), location: 0),
                .init(color: Color(red: 1, green: 0.45, blue: 0.24), location: 0.29),
                .init(color: Color(red: 0.94, green: 0.27, blue: 0.07), location: 0.58),
                .init(color: Color(red: 1, green: 0.47, blue: 0.06), location: 0.84),
                .init(color: Color(red: 1, green: 0.71, blue: 0.15), location: 1)
            ], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.75, y: 1)))
            .overlay {
                shape.fill(RadialGradient(colors: [Color(red: 0.68, green: 0.10, blue: 0.20).opacity(0.74), .clear],
                                          center: UnitPoint(x: 0.3, y: 0.48), startRadius: 0, endRadius: 24))
            }
            .overlay {
                shape.fill(RadialGradient(colors: [Color(red: 1, green: 0.94, blue: 0.42), .yellow.opacity(0.7), .clear],
                                          center: UnitPoint(x: 0.5, y: 0.8), startRadius: 0, endRadius: 15))
            }
            .overlay { shape.stroke(.orange.opacity(0.7), lineWidth: 0.35) }
            .animation(animated ? .easeInOut(duration: 0.5) : nil, value: activity == .optimizing)
    }

    private var eyes: some View {
        MascotEyes(straining: activity == .optimizing ? 1 : 0).stroke(Color(red: 1, green: 0.99, blue: 0.94), style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
    }
}

private struct MascotBody: Shape {
    var deformation: Double
    var roundness: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(deformation, roundness) }
        set { deformation = newValue.first; roundness = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let d = deformation
        let start = CGPoint(x: 28, y: 166)
        let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 26 - d * 4, y: 130), CGPoint(x: 49 - d * 3, y: 87), CGPoint(x: 78, y: 61)),
            (CGPoint(x: 99, y: 42 - d * 3), CGPoint(x: 124, y: 32 - d * 4), CGPoint(x: 151 + d * 3, y: 34 - d * 4)),
            (CGPoint(x: 186, y: 36 + d * 3), CGPoint(x: 211 + d * 4, y: 58), CGPoint(x: 229 + d * 3, y: 91)),
            (CGPoint(x: 247 + d * 4, y: 123), CGPoint(x: 259, y: 164), CGPoint(x: 248, y: 187)),
            (CGPoint(x: 240, y: 205), CGPoint(x: 212, y: 209), CGPoint(x: 169, y: 210)),
            (CGPoint(x: 126, y: 212), CGPoint(x: 75, y: 212), CGPoint(x: 50, y: 204)),
            (CGPoint(x: 36, y: 199), CGPoint(x: 29, y: 185), start)
        ]
        let radius = 92 + d * 2
        let step = 2 * Double.pi / Double(curves.count)
        let tangent = 4 / 3.0 * tan(step / 4) * radius
        func circle(_ angle: Double) -> CGPoint { CGPoint(x: 140 + cos(angle) * radius, y: 122 + sin(angle) * radius) }
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * roundness, y: a.y + (b.y - a.y) * roundness)
        }
        var path = Path()
        path.move(to: blend(start, circle(2.75)))
        for (index, curve) in curves.enumerated() {
            let a = 2.75 + Double(index) * step, b = a + step
            let p = circle(a), q = circle(b)
            let c1 = CGPoint(x: p.x - sin(a) * tangent, y: p.y + cos(a) * tangent)
            let c2 = CGPoint(x: q.x + sin(b) * tangent, y: q.y - cos(b) * tangent)
            path.addCurve(to: blend(curve.2, q), control1: blend(curve.0, c1), control2: blend(curve.1, c2))
        }
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: 0, y: 10).concatenating(CGAffineTransform(scaleX: rect.width / 278, y: rect.height / 278)))
    }
}

private struct MascotEyes: Shape {
    var straining: Double
    var animatableData: Double {
        get { straining }
        set { straining = newValue }
    }
    func path(in rect: CGRect) -> Path {
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * straining, y: a.y + (b.y - a.y) * straining)
        }
        var path = Path()
        path.move(to: blend(CGPoint(x: 141, y: 155), CGPoint(x: 141, y: 149)))
        path.addLine(to: blend(CGPoint(x: 152.5, y: 153.5), CGPoint(x: 154, y: 155)))
        path.addLine(to: blend(CGPoint(x: 164, y: 152), CGPoint(x: 141, y: 161)))
        path.move(to: blend(CGPoint(x: 201, y: 147), CGPoint(x: 219, y: 141)))
        path.addLine(to: blend(CGPoint(x: 210, y: 144.5), CGPoint(x: 206, y: 147)))
        path.addLine(to: blend(CGPoint(x: 219, y: 142), CGPoint(x: 219, y: 153)))
        return path.applying(CGAffineTransform(translationX: 0, y: 10).concatenating(CGAffineTransform(scaleX: rect.width / 278, y: rect.height / 278)))
    }
}
