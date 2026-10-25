import SwiftUI

/// Приватная админ-панель: добавить по slug, редактировать, удалить, менять баланс.
public struct AdminPanelView: View {
    @ObservedObject var store: KUpergramStore
    public init(store: KUpergramStore) { self.store = store }

    public var body: some View {
        NavigationStack {
            List {
                Section("Баланс Stars") { balanceEditor }
                Section("Добавить NFT по slug") {
                    NavigationLink("Добавить подарок") { AddNFTView(store: store) }
                }
                Section("Все подарки (\(store.nfts.count))") {
                    ForEach(store.nfts) { gift in
                        NavigationLink { EditNFTView(store: store, gift: gift) } label: {
                            HStack {
                                GiftImage(gift.imageUrl, corner: 8).frame(width: 40, height: 40)
                                VStack(alignment: .leading) {
                                    Text(gift.title)
                                    Text("владелец: \(store.name(of: gift.ownerId))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        let ids = idx.map { store.nfts[$0].id }
                        Task { for id in ids { await store.deleteNFT(id: id) } }
                    }
                }
            }
            .navigationTitle("Админ-панель")
            .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
            .task { await store.sync() }
        }
    }

    @ViewBuilder private var balanceEditor: some View {
        ForEach(store.users) { u in
            BalanceRow(store: store, user: u)
        }
    }
}

struct BalanceRow: View {
    @ObservedObject var store: KUpergramStore
    let user: KUser
    @State private var delta = 10
    @State private var busy = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(user.name)
                Text("\(store.balance(of: user.id)) ⭐").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("\(delta > 0 ? "+" : "")\(delta)", value: $delta, in: -1000...1000, step: 10)
                .labelsHidden()
                .fixedSize()
            Button {
                guard !busy else { return }
                busy = true
                Task { await store.adjustStars(userId: user.id, delta: delta, reason: "admin")
                       busy = false }
            } label: { busy ? AnyView(ProgressView()) : AnyView(Image(systemName: "checkmark.circle.fill")) }
            .disabled(busy)
        }
    }
}

// MARK: - добавление по slug
struct AddNFTView: View {
    @ObservedObject var store: KUpergramStore
    @Environment(\.dismiss) private var dismiss

    @State private var slug = ""
    @State private var name = ""
    @State private var number = ""
    @State private var model = ""
    @State private var backdrop = ""
    @State private var symbol = ""
    @State private var imageUrl = ""
    @State private var owner = "me"
    @State private var resolving = false
    @State private var saving = false

    var body: some View {
        Form {
            Section("Slug") {
                TextField("напр. ArtisanBrick-945", text: $slug)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Button {
                    guard !slug.isEmpty, !resolving else { return }
                    resolving = true
                    Task {
                        if let r = await store.resolve(slug: slug) {
                            name = r.name ?? name
                            number = r.number ?? number
                            model = r.model ?? model
                            backdrop = r.backdrop ?? backdrop
                            symbol = r.symbol ?? symbol
                            imageUrl = r.imageUrl ?? imageUrl
                        }
                        resolving = false
                    }
                } label: {
                    HStack { if resolving { ProgressView() }; Text("Получить данные") }
                }
            }
            Section("Данные (можно задать вручную)") {
                TextField("Название", text: $name)
                TextField("Номер", text: $number)
                TextField("Модель", text: $model)
                TextField("Фон", text: $backdrop)
                TextField("Символ", text: $symbol)
                TextField("URL изображения", text: $imageUrl)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section("Владелец") {
                Picker("Владелец", selection: $owner) {
                    ForEach(store.users) { Text($0.name).tag($0.id) }
                }.pickerStyle(.segmented)
            }
            Section {
                Button {
                    guard !saving else { return }
                    saving = true
                    Task {
                        await store.addNFT(NFTCreate(
                            slug: slug.isEmpty ? nil : slug,
                            name: name.isEmpty ? nil : name,
                            number: number.isEmpty ? nil : number,
                            model: model.isEmpty ? nil : model,
                            backdrop: backdrop.isEmpty ? nil : backdrop,
                            symbol: symbol.isEmpty ? nil : symbol,
                            imageUrl: imageUrl.isEmpty ? nil : imageUrl,
                            ownerId: owner))
                        saving = false
                        if store.lastError == nil { dismiss() }
                    }
                } label: {
                    HStack { if saving { ProgressView() }; Text("Добавить") }
                        .frame(maxWidth: .infinity)
                }.disabled(saving).buttonStyle(.borderedProminent)
            }
            Section { VisualBadge() }
        }
        .navigationTitle("Новый подарок")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - редактирование
struct EditNFTView: View {
    @ObservedObject var store: KUpergramStore
    let gift: GiftCard
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var number: String
    @State private var model: String
    @State private var backdrop: String
    @State private var symbol: String
    @State private var imageUrl: String
    @State private var saving = false

    init(store: KUpergramStore, gift: GiftCard) {
        self.store = store; self.gift = gift
        _name = State(initialValue: gift.name ?? "")
        _number = State(initialValue: gift.number ?? "")
        _model = State(initialValue: gift.model ?? "")
        _backdrop = State(initialValue: gift.backdrop ?? "")
        _symbol = State(initialValue: gift.symbol ?? "")
        _imageUrl = State(initialValue: gift.imageUrl ?? "")
    }

    var body: some View {
        Form {
            Section("Характеристики") {
                TextField("Название", text: $name)
                TextField("Номер", text: $number)
                TextField("Модель", text: $model)
                TextField("Фон", text: $backdrop)
                TextField("Символ", text: $symbol)
                TextField("URL изображения", text: $imageUrl)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section("Владелец / передача") {
                ForEach(store.users) { u in
                    if u.id != gift.ownerId {
                        Button("Передать → \(u.name)") {
                            Task { await store.transfer(id: gift.id, to: u.id) }
                        }
                    }
                }
            }
            Section {
                Button {
                    guard !saving else { return }
                    saving = true
                    Task {
                        await store.patchNFT(id: gift.id, payload: NFTPatch(
                            name: name, number: number, model: model,
                            backdrop: backdrop, symbol: symbol, imageUrl: imageUrl))
                        saving = false
                        if store.lastError == nil { dismiss() }
                    }
                } label: {
                    HStack { if saving { ProgressView() }; Text("Сохранить") }
                        .frame(maxWidth: .infinity)
                }.disabled(saving).buttonStyle(.borderedProminent)

                Button("Удалить", role: .destructive) {
                    Task { await store.deleteNFT(id: gift.id); dismiss() }
                }
            }
        }
        .navigationTitle(gift.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
