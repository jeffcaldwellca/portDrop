import SwiftUI

struct KindChip: View {
    let kind: ServiceKind
    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(kind.tint.opacity(0.25), lineWidth: 0.5))
    }
}
