import SwiftUI

struct ShimmerView: View {
    let rowCount: Int

    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: 12) {
                    shimmerBlock(width: 42, height: 42)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        shimmerBlock(width: 150, height: 12)
                        shimmerBlock(width: 220, height: 10)
                        shimmerBlock(width: 180, height: 10)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func shimmerBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.35),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.7)
                    .offset(x: phase * proxy.size.width)
                }
                .clipped()
            }
    }
}

#Preview {
    ShimmerView(rowCount: 3)
        .padding()
}
