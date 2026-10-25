import SwiftUI

/// Палитра в духе Telegram iOS, адаптивная к светлой/тёмной теме.
public enum KTheme {
    public static let accent = Color("KAccent", bundle: nil) // определи в Assets; fallback ниже
    public static let tgBlue = Color(red: 0.0, green: 0.48, blue: 1.0)      // #007AFF
    public static let star = Color(red: 1.0, green: 0.74, blue: 0.0)        // золото звезды
    public static let cardLight = Color(.secondarySystemBackground)
    public static let cardDark = Color(.tertiarySystemBackground)
    public static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cardDark : cardLight
    }
}

/// Бейдж «визуальный актив» — обязательная пометка, что это НЕ настоящий
/// Telegram-подарок/блокчейн-NFT.
public struct VisualBadge: View {
    public init() {}
    public var body: some View {
        Text("Визуальный · KUpergram")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// Плашка баланса звёзд.
public struct StarsPill: View {
    let amount: Int
    public init(_ amount: Int) { self.amount = amount }
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").foregroundStyle(KTheme.star)
            Text("\(amount)").font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Баннер ошибки сервера поверх контента.
public struct ErrorBanner: View {
    @Binding var message: String?
    public init(message: Binding<String?>) { _message = message }
    public var body: some View {
        if let msg = message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(msg).font(.footnote)
                Spacer()
                Button { message = nil } label: { Image(systemName: "xmark") }
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Асинхронная картинка подарка с плейсхолдером.
public struct GiftImage: View {
    let urlString: String?
    var corner: CGFloat = 16
    public init(_ urlString: String?, corner: CGFloat = 16) {
        self.urlString = urlString; self.corner = corner
    }
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [KTheme.tgBlue.opacity(0.25), KTheme.star.opacity(0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let s = urlString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().padding(8)
                    case .failure: Image(systemName: "gift.fill").font(.largeTitle).foregroundStyle(.secondary)
                    default: ProgressView()
                    }
                }
            } else {
                Image(systemName: "gift.fill").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
