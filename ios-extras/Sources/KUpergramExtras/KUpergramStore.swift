import Foundation
import SwiftUI

/// Единое состояние KUpergram: баланс Stars, коллекция NFT, история и подарки.
/// Держит локальный кэш (мгновенный старт оффлайн) и синхронизируется с сервером.
@MainActor
public final class KUpergramStore: ObservableObject {

    // Текущее состояние (из сети или кэша)
    @Published public private(set) var users: [KUser] = []
    @Published public private(set) var stars: [String: Int] = [:]
    @Published public private(set) var nfts: [GiftCard] = []
    @Published public private(set) var history: [StarsEntry] = []
    @Published public private(set) var gifts: [GiftEvent] = []

    @Published public private(set) var isSyncing = false
    @Published public var lastError: String?

    /// Текущий пользователь этого устройства ("me" или "friend").
    @Published public var currentUserId: String

    private let api: KUpergramAPI
    private let cacheURL: URL
    /// Операции «в полёте» — вторая попытка того же действия игнорируется (анти-дабл-тап).
    private var inFlight = Set<String>()

    /// Есть ли у этого устройства админ-права (скрывает/показывает админ-панель).
    public let isAdmin: Bool

    public init(api: KUpergramAPI, currentUserId: String = "me", isAdmin: Bool = false) {
        self.api = api
        self.currentUserId = currentUserId
        self.isAdmin = isAdmin
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.cacheURL = dir.appendingPathComponent("kupergram_state.json")
        loadCache()
    }

    // MARK: - производные данные
    public var myBalance: Int { stars[currentUserId] ?? 0 }
    public func balance(of userId: String) -> Int { stars[userId] ?? 0 }
    public func nfts(ownedBy userId: String) -> [GiftCard] { nfts.filter { $0.ownerId == userId } }
    public var myNFTs: [GiftCard] { nfts(ownedBy: currentUserId) }
    public func name(of userId: String) -> String { users.first { $0.id == userId }?.name ?? userId }
    public func otherUserId() -> String { currentUserId == "me" ? "friend" : "me" }

    // MARK: - синхронизация
    public func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let state = try await api.fetchState()
            apply(state)
            saveCache(state)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ s: SyncState) {
        users = s.users; stars = s.stars; nfts = s.nfts
        history = s.history; gifts = s.gifts
    }

    // MARK: - действия (каждое синкает состояние после успеха)

    public func adjustStars(userId: String, delta: Int, reason: String?) async {
        await guarded("adjust-\(userId)") {
            _ = try await self.api.adjustStars(userId: userId, delta: delta, reason: reason)
        }
    }

    public func purchase(_ payload: PurchasePayload) async {
        // ключ идемпотентности привязан к операции на всё время её жизни
        let key = UUID().uuidString
        await guarded("purchase-\(payload.slug ?? payload.name ?? key)") {
            _ = try await self.api.purchase(payload, idempotencyKey: key)
        }
    }

    public func upgrade(id: String, payload: UpgradePayload) async {
        let key = UUID().uuidString
        await guarded("upgrade-\(id)") {
            _ = try await self.api.upgrade(id: id, payload: payload, idempotencyKey: key)
        }
    }

    public func gift(id: String, to toUser: String, starsCost: Int, message: String?) async {
        let key = UUID().uuidString
        await guarded("gift-\(id)") {
            let payload = GiftPayload(toUser: toUser, starsCost: starsCost, message: message)
            _ = try await self.api.gift(id: id, payload: payload, idempotencyKey: key)
        }
    }

    public func addNFT(_ payload: NFTCreate) async {
        await guarded("add-\(payload.slug ?? payload.name ?? UUID().uuidString)") {
            _ = try await self.api.addNFT(payload)
        }
    }

    public func transfer(id: String, to toUser: String) async {
        await guarded("transfer-\(id)") { _ = try await self.api.transfer(id: id, toUser: toUser) }
    }

    public func patchNFT(id: String, payload: NFTPatch) async {
        await guarded("patch-\(id)") { _ = try await self.api.patchNFT(id: id, payload: payload) }
    }

    public func deleteNFT(id: String) async {
        await guarded("delete-\(id)") { try await self.api.deleteNFT(id: id) }
    }

    public func resolve(slug: String) async -> ResolvedSlug? {
        do { return try await api.resolve(slug: slug) }
        catch { lastError = (error as? LocalizedError)?.errorDescription; return nil }
    }

    /// Выполнить действие с защитой от повторного запуска + авто-синк после.
    private func guarded(_ opKey: String, _ action: @escaping () async throws -> Void) async {
        guard !inFlight.contains(opKey) else { return }   // анти-дабл-тап
        inFlight.insert(opKey)
        defer { inFlight.remove(opKey) }
        do {
            try await action()
            await sync()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func isBusy(_ opKey: String) -> Bool { inFlight.contains(opKey) }

    // MARK: - локальный кэш
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let s = try? JSONDecoder().decode(SyncState.self, from: data) else { return }
        apply(s)
    }

    private func saveCache(_ s: SyncState) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
