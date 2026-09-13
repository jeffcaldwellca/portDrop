import SwiftUI

struct DockerChip: View {
    static let tint: Color = .blue
    var body: some View {
        Label("Docker", systemImage: "shippingbox")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Self.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Self.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Self.tint.opacity(0.25), lineWidth: 0.5))
    }
}
