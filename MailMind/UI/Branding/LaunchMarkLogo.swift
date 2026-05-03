import SwiftUI

/// `LaunchMark` rendered as a template so it stays crisp and adapts to light/dark backgrounds.
struct LaunchMarkLogo: View {
    let squareSide: CGFloat?
    let cappedHeight: CGFloat?

    init(size: CGFloat) {
        squareSide = size
        cappedHeight = nil
    }

    init(height: CGFloat) {
        squareSide = nil
        cappedHeight = height
    }

    var body: some View {
        Group {
            if let side = squareSide {
                mark.frame(width: side, height: side)
            } else if let h = cappedHeight {
                mark.frame(height: h)
            }
        }
    }

    private var mark: some View {
        Image("LaunchMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
    }
}
