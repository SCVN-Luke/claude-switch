import SwiftUI

/// Controls the Guide can point at. Real views tag themselves with `.guideTarget(_:)`;
/// outside the Guide the tag has no visible effect.
enum GuideTarget: Hashable {
    case menuBarIcon, manageProfiles, addProfile, alertPrimary, switchButton, profileRow2, switchAndCarry
}

struct GuideAnchorKey: PreferenceKey {
    static let defaultValue: [GuideTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [GuideTarget: Anchor<CGRect>], nextValue: () -> [GuideTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func guideTarget(_ target: GuideTarget) -> some View {
        anchorPreference(key: GuideAnchorKey.self, value: .bounds) { [target: $0] }
    }

    /// Dims everything except `targets` and circles each of them in red.
    func guideHighlight(_ targets: [GuideTarget]) -> some View {
        overlayPreferenceValue(GuideAnchorKey.self) { anchors in
            GeometryReader { geo in
                let rects = targets.compactMap { anchors[$0].map { geo[$0].insetBy(dx: -6, dy: -5) } }
                if !rects.isEmpty {
                    ZStack {
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            for r in rects { p.addRoundedRect(in: r, cornerSize: CGSize(width: 8, height: 8)) }
                        }
                        .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                        ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red, lineWidth: 3)
                                .frame(width: r.width, height: r.height)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
