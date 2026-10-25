import SwiftUI

/// Анимация передачи подарка с конфетти (визуальный эффект при дарении).
public struct GiftAnimationOverlay: View {
    @Binding var isPresented: Bool
    let title: String
    var onFinished: () -> Void = {}

    @State private var lift = false
    @State private var confetti = false

    public init(isPresented: Binding<Bool>, title: String, onFinished: @escaping () -> Void = {}) {
        _isPresented = isPresented; self.title = title; self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(isPresented ? 0.45 : 0).ignoresSafeArea()
            if isPresented {
                ConfettiView(active: confetti)
                VStack(spacing: 14) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(KTheme.tgBlue)
                        .scaleEffect(lift ? 1.0 : 0.3)
                        .offset(y: lift ? -20 : 60)
                        .rotationEffect(.degrees(lift ? 0 : -15))
                    Text("Подарок отправлен")
                        .font(.headline).foregroundStyle(.white)
                    Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue { runSequence() }
        }
    }

    private func runSequence() {
        lift = false; confetti = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { lift = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.15)) { confetti = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut) { isPresented = false }
            onFinished()
        }
    }
}

/// Простое конфетти на чистом SwiftUI (без сторонних либ).
struct ConfettiView: View {
    let active: Bool
    private let pieces = (0..<40).map { _ in ConfettiPiece.random() }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    Rectangle()
                        .fill(p.color)
                        .frame(width: 7, height: 11)
                        .rotationEffect(.degrees(active ? p.rotation : 0))
                        .position(x: p.x * geo.size.width,
                                  y: active ? geo.size.height + 40 : -40)
                        .opacity(active ? 1 : 0)
                        .animation(.easeIn(duration: p.duration).delay(p.delay), value: active)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat, rotation: Double, duration: Double, delay: Double, color: Color
    static func random() -> ConfettiPiece {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, KTheme.star, KTheme.tgBlue]
        return ConfettiPiece(x: .random(in: 0...1),
                             rotation: .random(in: 180...720),
                             duration: .random(in: 1.0...1.8),
                             delay: .random(in: 0...0.3),
                             color: colors.randomElement()!)
    }
}
