import SwiftUI

/// Детали подарка: характеристики, «Подарить», «Апгрейд».
public struct GiftDetailView: View {
    @ObservedObject var store: KUpergramStore
    let gift: GiftCard

    @Environment(\.colorScheme) private var scheme
    @State private var showGiftSheet = false
    @State private var showUpgradeSheet = false
    @State private var showAnimation = false

    public init(store: KUpergramStore, gift: GiftCard) {
        self.store = store; self.gift = gift
    }

    // актуальная версия карточки из стора (после синка владелец мог смениться)
    private var current: GiftCard? { store.nfts.first { $0.id == gift.id } }
    private var isMine: Bool { (current?.ownerId ?? gift.ownerId) == store.currentUserId }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GiftImage(gift.imageUrl, corner: 24)
                    .frame(height: 240).padding(.horizontal)

                VStack(spacing: 6) {
                    Text(gift.title).font(.title2.bold())
                    if let n = gift.number { Text("#\(n)").foregroundStyle(.secondary) }
                    VisualBadge()
                }

                VStack(spacing: 0) {
                    specRow("Модель", gift.model)
                    specRow("Фон", gift.backdrop)
                    specRow("Символ", gift.symbol)
                    specRow("Slug", gift.slug)
                    specRow("Владелец", store.name(of: current?.ownerId ?? gift.ownerId))
                    specRow("Добавлен", gift.addedDate.formatted(date: .abbreviated, time: .shortened))
                    specRow("Статус", gift.isCollectible ? "Коллекционный" : "Обычный")
                }
                .background(KTheme.card(scheme), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                if isMine {
                    VStack(spacing: 12) {
                        Button { showGiftSheet = true } label: {
                            Label("Подарить", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(KTheme.tgBlue)

                        if !gift.isCollectible {
                            Button { showUpgradeSheet = true } label: {
                                Label("Апгрейд в коллекционный", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Text("Этот подарок у \(store.name(of: current?.ownerId ?? gift.ownerId))")
                        .foregroundStyle(.secondary).padding()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(gift.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
        .overlay { GiftAnimationOverlay(isPresented: $showAnimation, title: gift.title) }
        .sheet(isPresented: $showGiftSheet) {
            GiftSendSheet(store: store, gift: gift) { showAnimation = true }
        }
        .sheet(isPresented: $showUpgradeSheet) {
            UpgradeSheet(store: store, gift: gift)
        }
    }

    @ViewBuilder private func specRow(_ key: String, _ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            HStack {
                Text(key).foregroundStyle(.secondary)
                Spacer()
                Text(v).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            Divider().padding(.leading, 16)
        }
    }
}

// MARK: - Лист отправки подарка
struct GiftSendSheet: View {
    @ObservedObject var store: KUpergramStore
    let gift: GiftCard
    var onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var starsCost = 0
    @State private var message = ""
    @State private var sending = false

    private var recipient: String { store.otherUserId() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Получатель") {
                    Text(store.name(of: recipient))
                }
                Section("Стоимость (визуальные Stars)") {
                    Stepper("\(starsCost) ⭐", value: $starsCost, in: 0...store.myBalance)
                    Text("0 = подарить бесплатно").font(.caption).foregroundStyle(.secondary)
                }
                Section("Сообщение") {
                    TextField("Необязательно", text: $message)
                }
                Section {
                    Button {
                        guard !sending else { return }   // анти-дабл-тап в UI
                        sending = true
                        Task {
                            await store.gift(id: gift.id, to: recipient,
                                             starsCost: starsCost,
                                             message: message.isEmpty ? nil : message)
                            sending = false
                            if store.lastError == nil { onSent(); dismiss() }
                        }
                    } label: {
                        HStack {
                            if sending { ProgressView() }
                            Text("Подарить \(store.name(of: recipient))")
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(sending)
                    .buttonStyle(.borderedProminent).tint(KTheme.tgBlue)
                }
            }
            .navigationTitle("Подарить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Лист апгрейда
struct UpgradeSheet: View {
    @ObservedObject var store: KUpergramStore
    let gift: GiftCard

    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var backdrop = ""
    @State private var symbol = ""
    @State private var starsCost = 0
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Характеристики коллекционного") {
                    TextField("Модель", text: $model)
                    TextField("Фон", text: $backdrop)
                    TextField("Символ", text: $symbol)
                }
                Section("Стоимость") {
                    Stepper("\(starsCost) ⭐", value: $starsCost, in: 0...store.myBalance)
                }
                Section {
                    Button {
                        guard !working else { return }
                        working = true
                        Task {
                            await store.upgrade(id: gift.id, payload: UpgradePayload(
                                starsCost: starsCost,
                                model: model.isEmpty ? nil : model,
                                backdrop: backdrop.isEmpty ? nil : backdrop,
                                symbol: symbol.isEmpty ? nil : symbol))
                            working = false
                            if store.lastError == nil { dismiss() }
                        }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text("Апгрейднуть")
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(working)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Апгрейд")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
