import SwiftUI

/// История подарков: «Подарил» и «Получил» для текущего пользователя.
public struct GiftHistoryView: View {
    @ObservedObject var store: KUpergramStore
    public init(store: KUpergramStore) { self.store = store }

    public var body: some View {
        NavigationStack {
            List {
                if relevant.isEmpty {
                    Text("Пока нет подарков").foregroundStyle(.secondary)
                }
                ForEach(relevant) { event in
                    let sent = event.fromUser == store.currentUserId
                    HStack(spacing: 12) {
                        Image(systemName: sent ? "paperplane.fill" : "gift.fill")
                            .foregroundStyle(sent ? KTheme.tgBlue : .green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sent
                                 ? "Подарил → \(store.name(of: event.toUser))"
                                 : "Получил ← \(store.name(of: event.fromUser))")
                                .font(.body.weight(.medium))
                            Text(giftTitle(event.nftId))
                                .font(.caption).foregroundStyle(.secondary)
                            if let m = event.message, !m.isEmpty {
                                Text("«\(m)»").font(.caption).italic().foregroundStyle(.secondary)
                            }
                            Text(event.date, style: .date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if event.starsCost > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").foregroundStyle(KTheme.star)
                                Text("\(event.starsCost)").monospacedDigit()
                            }.font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Подарки")
            .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
            .refreshable { await store.sync() }
            .task { await store.sync() }
        }
    }

    private var relevant: [GiftEvent] {
        store.gifts.filter { $0.fromUser == store.currentUserId || $0.toUser == store.currentUserId }
    }

    private func giftTitle(_ nftId: String) -> String {
        store.nfts.first { $0.id == nftId }?.title ?? "Подарок"
    }
}
