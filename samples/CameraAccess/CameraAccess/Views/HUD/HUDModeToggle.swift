import SwiftUI

struct HUDModeToggle: View {
    @Binding var isHUDMode: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                isHUDMode.toggle()
            }
        } label: {
            Image(systemName: isHUDMode ? "rectangle.stack" : "eyeglasses")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
    }
}
