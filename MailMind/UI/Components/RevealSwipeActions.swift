import SwiftUI

enum RevealSwipeHaptic {
    case none
    case success
    case warning
    case error

    func fire() {
        switch self {
        case .none:
            break
        case .success:
            HapticManager.success()
        case .warning:
            HapticManager.warning()
        case .error:
            HapticManager.error()
        }
    }
}

struct RevealSwipeAction {
    let title: String
    let systemImage: String
    let tint: Color
    let haptic: RevealSwipeHaptic
    let handler: () -> Void

    init(
        title: String,
        systemImage: String,
        tint: Color,
        haptic: RevealSwipeHaptic = .success,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.haptic = haptic
        self.handler = handler
    }
}

struct RevealSwipeStyle {
    let commitThreshold: CGFloat
    let maxRevealDistance: CGFloat
    let horizontalActivationDistance: CGFloat
    let horizontalDominanceRatio: CGFloat
    let overflowResistance: CGFloat
    let overflowAllowance: CGFloat
    let actionHorizontalPadding: CGFloat
    let cornerRadius: CGFloat
    let resetAnimation: Animation
    let actionDelay: TimeInterval
    /// Category inbox: square reveal tint, rounded clipping on the sliding row only while dragging. Archive: classic uniformly rounded swipe stack.
    let movingLayerRoundedOnlyWhileDragging: Bool

    static let emailRow = RevealSwipeStyle(
        commitThreshold: 118,
        maxRevealDistance: 124,
        horizontalActivationDistance: 24,
        horizontalDominanceRatio: 1.9,
        overflowResistance: 0.16,
        overflowAllowance: 30,
        actionHorizontalPadding: 26,
        cornerRadius: 12,
        resetAnimation: .interactiveSpring(response: 0.28, dampingFraction: 0.86),
        actionDelay: 0.1,
        movingLayerRoundedOnlyWhileDragging: true
    )

    static let archiveRow = RevealSwipeStyle(
        commitThreshold: 118,
        maxRevealDistance: 124,
        horizontalActivationDistance: 24,
        horizontalDominanceRatio: 1.9,
        overflowResistance: 0.16,
        overflowAllowance: 30,
        actionHorizontalPadding: 26,
        cornerRadius: 12,
        resetAnimation: .interactiveSpring(response: 0.28, dampingFraction: 0.86),
        actionDelay: 0.1,
        movingLayerRoundedOnlyWhileDragging: false
    )
}

extension View {
    func revealSwipeActions(
        leading: RevealSwipeAction? = nil,
        trailing: RevealSwipeAction? = nil,
        style: RevealSwipeStyle
    ) -> some View {
        modifier(RevealSwipeActionsModifier(leading: leading, trailing: trailing, style: style))
    }
}

private enum RevealSwipeAxis {
    case horizontal
    case vertical
}

private struct RevealSwipeActionsModifier: ViewModifier {
    let leading: RevealSwipeAction?
    let trailing: RevealSwipeAction?
    let style: RevealSwipeStyle

    @State private var horizontalOffset: CGFloat = 0
    @State private var activeAxis: RevealSwipeAxis?

    @ViewBuilder
    func body(content: Content) -> some View {
        if leading == nil && trailing == nil {
            content
        } else if style.movingLayerRoundedOnlyWhileDragging {
            ZStack {
                categorySwipeLayers(content)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)
        } else {
            ZStack {
                archiveSwipeLayers(content)
            }
            .clipShape(rowShape)
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)
        }
    }

    @ViewBuilder
    private func categorySwipeLayers(_ row: Content) -> some View {
        if horizontalOffset != 0 {
            actionBackground
        }

        Group {
            if horizontalOffset != 0 {
                row.clipShape(rowShape)
            } else {
                row
            }
        }
        .offset(x: horizontalOffset)
    }

    @ViewBuilder
    private func archiveSwipeLayers(_ row: Content) -> some View {
        if horizontalOffset != 0 {
            actionBackground
                .clipShape(rowShape)
        }

        row
            .clipShape(rowShape)
            .offset(x: horizontalOffset)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var actionBackground: some View {
        if horizontalOffset > 0, let leading {
            actionPanel(for: leading, alignment: .leading)
        } else if horizontalOffset < 0, let trailing {
            actionPanel(for: trailing, alignment: .trailing)
        } else {
            Color.clear
        }
    }

    private func actionPanel(for action: RevealSwipeAction, alignment: Alignment) -> some View {
        let distance = abs(horizontalOffset)
        let revealProgress = min(1, distance / style.maxRevealDistance)
        let commitProgress = min(1, distance / style.commitThreshold)
        let iconScale = 0.82 + (0.22 * revealProgress) + (0.18 * commitProgress)

        return ZStack(alignment: alignment) {
            Group {
                if style.movingLayerRoundedOnlyWhileDragging {
                    Rectangle().fill(action.tint)
                } else {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(action.tint)
                }
            }

            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .scaleEffect(iconScale)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.7), value: commitProgress >= 1)

                Text(action.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .opacity(0.68 + (0.32 * revealProgress))
            .padding(.horizontal, style.actionHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard isHorizontalDrag(value) else {
                    return
                }

                horizontalOffset = constrainedOffset(for: value.translation.width)
            }
            .onEnded { value in
                defer { activeAxis = nil }

                guard activeAxis == .horizontal,
                      let action = committedAction(for: value) else {
                    resetOffset()
                    return
                }

                action.haptic.fire()
                resetOffset()

                DispatchQueue.main.asyncAfter(deadline: .now() + style.actionDelay) {
                    action.handler()
                }
            }
    }

    private func isHorizontalDrag(_ value: DragGesture.Value) -> Bool {
        if let activeAxis {
            return activeAxis == .horizontal
        }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if verticalDistance >= 8 && verticalDistance >= horizontalDistance * 0.58 {
            activeAxis = .vertical
            horizontalOffset = 0
            return false
        }

        if horizontalDistance >= style.horizontalActivationDistance
            && horizontalDistance > verticalDistance * style.horizontalDominanceRatio {
            activeAxis = .horizontal
            return true
        }

        if verticalDistance > horizontalDistance {
            activeAxis = .vertical
            horizontalOffset = 0
        }

        return false
    }

    private func constrainedOffset(for translation: CGFloat) -> CGFloat {
        guard translation != 0 else {
            return 0
        }

        if translation > 0, leading == nil {
            return 0
        }

        if translation < 0, trailing == nil {
            return 0
        }

        let direction: CGFloat = translation > 0 ? 1 : -1
        let distance = abs(translation)

        guard distance > style.maxRevealDistance else {
            return translation
        }

        let overflow = min(
            style.overflowAllowance,
            (distance - style.maxRevealDistance) * style.overflowResistance
        )

        return direction * (style.maxRevealDistance + overflow)
    }

    private func committedAction(for value: DragGesture.Value) -> RevealSwipeAction? {
        let translation = value.translation.width
        let distance = abs(translation)

        guard distance >= style.commitThreshold else {
            return nil
        }

        if translation > 0 {
            return leading
        }

        if translation < 0 {
            return trailing
        }

        return nil
    }

    private func resetOffset() {
        withAnimation(style.resetAnimation) {
            horizontalOffset = 0
        }
    }
}
