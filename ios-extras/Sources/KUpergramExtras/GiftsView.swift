import SwiftUI

/// Коллекция подарков текущего пользователя — сетка карточек.
public struct GiftsView: View {
    @ObservedObject var store: KUpergramStore
    public init(store: KUpergramStore) { self.store = store }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                if store.myNFTs.isEmpty {
                    ContentUnavailableView("Нет подарков",
                        systemImage: "gift",
                        description: Text("Добавь их в магазине или через админ-панель"))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.myNFTs) { gift in
                            NavigationLink {
                                GiftDetailView(store: store, gift: gift)
                            } label: {
                                GiftCardTile(gift: gift)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Gifts")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { StarsPill(store.myBalance) } }
            .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
            .refreshable { await store.sync() }
            .task { await store.sync() }
        }
    }
}

/// Карточка подарка в сетке.
public struct GiftCardTile: View {
    let gift: GiftCard
    @Environment(\.colorScheme) private var scheme
    public init(gift: GiftCard) { self.gift = gift }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                GiftImage(gift.imageUrl)
                    .aspectRatio(1, contentMode: .fit)
                if gift.isCollectible {
                    Image(systemName: "seal.fill")
                        .foregroundStyle(KTheme.star)
                        .padding(6)
                }
            }
            Text(gift.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let n = gift.number {
                Text("#\(n)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(KTheme.card(scheme), in: RoundedRectangle(cornerRadius: 18))
    }
}

extension GiftCard {
    /// Коллекционный флаг приходит с сервера как is_collectible (0/1 → Bool).
    var isCollectible: Bool { (collectibleFlag ?? 0) != 0 }
}
