import SwiftUI

/// Магазин: покупка визуальных подарков за внутренние Stars (в т.ч. за 0).
public struct ShopView: View {
    @ObservedObject var store: KUpergramStore
    public init(store: KUpergramStore) { self.store = store }

    @Environment(\.colorScheme) private var scheme
    @State private var buying: String?   // id товара в процессе покупки

    // Витрина (каталог косметических подарков). Можно расширять/грузить с сервера.
    private let catalog: [ShopItem] = ShopItem.defaultCatalog

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(catalog) { item in
                        VStack(spacing: 8) {
                            GiftImage(item.imageUrl).aspectRatio(1, contentMode: .fit)
                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Button {
                                buy(item)
                            } label: {
                                HStack(spacing: 4) {
                                    if buying == item.id { ProgressView() }
                                    else if item.price == 0 { Text("Бесплатно") }
                                    else { Image(systemName: "star.fill"); Text("\(item.price)") }
                                }
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(item.price == 0 ? .green : KTheme.tgBlue)
                            .disabled(buying != nil || store.myBalance < item.price)
                        }
                        .padding(10)
                        .background(KTheme.card(scheme), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding()
            }
            .navigationTitle("Магазин")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { StarsPill(store.myBalance) } }
            .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
            .task { await store.sync() }
        }
    }

    private func buy(_ item: ShopItem) {
        guard buying == nil else { return }   // анти-дабл-тап
        buying = item.id
        Task {
            await store.purchase(PurchasePayload(
                ownerId: store.currentUserId,
                starsCost: item.price,
                collectible: item.collectible,
                slug: item.slug,
                name: item.name,
                model: item.model,
                imageUrl: item.imageUrl))
            buying = nil
        }
    }
}

struct ShopItem: Identifiable {
    let id = UUID().uuidString
    let name: String
    let price: Int
    let collectible: Bool
    var slug: String? = nil
    var model: String? = nil
    var imageUrl: String? = nil

    static let defaultCatalog: [ShopItem] = [
        ShopItem(name: "Jelly Bunny", price: 0, collectible: false, slug: "JellyBunny-37010"),
        ShopItem(name: "Lunar Snake", price: 25, collectible: true, slug: "LunarSnake-91679"),
        ShopItem(name: "Artisan Brick", price: 50, collectible: true, slug: "ArtisanBrick-945"),
        ShopItem(name: "Snoop Dogg", price: 100, collectible: true, slug: "SnoopDogg-103788"),
    ]
}
