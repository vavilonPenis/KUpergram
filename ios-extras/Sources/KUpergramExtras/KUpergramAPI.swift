import Foundation

/// Сетевой клиент к серверу синхронизации KUpergram.
/// Все звёзды и подарки здесь — ВИЗУАЛЬНАЯ экономика форка, отдельная от
/// настоящих активов Telegram.
public final class KUpergramAPI {

    public struct Config {
        public var baseURL: URL
        public var adminToken: String
        public init(baseURL: URL, adminToken: String) {
            self.baseURL = baseURL
            self.adminToken = adminToken
        }
    }

    public enum APIError: LocalizedError {
        case http(Int, String)
        case transport(Error)
        case decoding(Error)
        public var errorDescription: String? {
            switch self {
            case .http(let code, let detail): return "HTTP \(code): \(detail)"
            case .transport(let e): return "Сеть: \(e.localizedDescription)"
            case .decoding(let e): return "Разбор ответа: \(e.localizedDescription)"
            }
        }
    }

    private let config: Config
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - низкоуровневый запрос
    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: Encodable? = nil,
        idempotencyKey: String? = nil,
        as type: T.Type
    ) async throws -> T {
        var comps = URLComponents(url: config.baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if let query = query {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(config.adminToken, forHTTPHeaderField: "X-Admin-Token")
        if let key = idempotencyKey {
            req.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? decoder.decode(ErrorBody.self, from: data))?.detail
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(code, detail)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private struct ErrorBody: Decodable { let detail: String }

    // MARK: - публичные вызовы

    /// Полный снимок состояния для синхронизации.
    public func fetchState() async throws -> SyncState {
        try await request("state", as: SyncState.self)
    }

    /// Изменить баланс звёзд (админ-панель).
    @discardableResult
    public func adjustStars(userId: String, delta: Int, reason: String? = nil) async throws -> StarsBalance {
        try await request("stars/adjust", method: "POST",
                          body: ["user_id": AnyEncodable(userId),
                                 "delta": AnyEncodable(delta),
                                 "reason": AnyEncodable(reason)],
                          as: StarsBalance.self)
    }

    /// Резолв карточки по slug с публичного источника (для админки/магазина).
    public func resolve(slug: String) async throws -> ResolvedSlug {
        try await request("nft/resolve", query: ["slug": slug], as: ResolvedSlug.self)
    }

    /// Добавить карточку (админка). Возвращает id; актуальные данные берутся из /state.
    @discardableResult
    public func addNFT(_ payload: NFTCreate) async throws -> CreatedRef {
        try await request("nft", method: "POST", body: payload, as: CreatedRef.self)
    }

    /// Купить визуальный подарок за внутренние Stars (cost может быть 0).
    @discardableResult
    public func purchase(_ payload: PurchasePayload, idempotencyKey: String = UUID().uuidString) async throws -> CreatedRef {
        try await request("shop/purchase", method: "POST", body: payload,
                          idempotencyKey: idempotencyKey, as: CreatedRef.self)
    }

    /// Апгрейд обычного подарка в коллекционный.
    public func upgrade(id: String, payload: UpgradePayload, idempotencyKey: String = UUID().uuidString) async throws -> UpgradeResult {
        try await request("nft/\(id)/upgrade", method: "POST", body: payload,
                          idempotencyKey: idempotencyKey, as: UpgradeResult.self)
    }

    /// Подарить карточку другому пользователю (idempotency защищает от двойного списания).
    public func gift(id: String, payload: GiftPayload, idempotencyKey: String = UUID().uuidString) async throws -> GiftResult {
        try await request("nft/\(id)/gift", method: "POST", body: payload,
                          idempotencyKey: idempotencyKey, as: GiftResult.self)
    }

    /// Админская передача владельца (без списания звёзд, без проверки владельца).
    public func transfer(id: String, toUser: String) async throws -> [String: String] {
        try await request("nft/\(id)/transfer", method: "POST",
                          body: ["to_user": toUser], as: [String: String].self)
    }

    public func patchNFT(id: String, payload: NFTPatch) async throws -> [String: String] {
        try await request("nft/\(id)", method: "PATCH", body: payload, as: [String: String].self)
    }

    public func deleteNFT(id: String) async throws {
        _ = try await request("nft/\(id)", method: "DELETE", as: [String: String].self)
    }
}

// MARK: - DTO для запросов/ответов

public struct CreatedRef: Codable { public let id: String }

public struct StarsBalance: Codable { public let userId: String; public let balance: Int
    enum CodingKeys: String, CodingKey { case userId = "user_id"; case balance } }

public struct NFTCreate: Encodable {
    public var slug: String?; public var name: String?; public var number: String?
    public var model: String?; public var backdrop: String?; public var symbol: String?
    public var imageUrl: String?; public var ownerId: String = "me"
    enum CodingKeys: String, CodingKey {
        case slug, name, number, model, backdrop, symbol
        case imageUrl = "image_url"; case ownerId = "owner_id"
    }
    public init(slug: String? = nil, name: String? = nil, number: String? = nil,
                model: String? = nil, backdrop: String? = nil, symbol: String? = nil,
                imageUrl: String? = nil, ownerId: String = "me") {
        self.slug = slug; self.name = name; self.number = number; self.model = model
        self.backdrop = backdrop; self.symbol = symbol; self.imageUrl = imageUrl; self.ownerId = ownerId
    }
}

public struct PurchasePayload: Encodable {
    public var ownerId: String = "me"; public var starsCost: Int = 0; public var collectible: Bool = false
    public var slug: String?; public var name: String?; public var number: String?
    public var model: String?; public var backdrop: String?; public var symbol: String?; public var imageUrl: String?
    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id", starsCost = "stars_cost", collectible
        case slug, name, number, model, backdrop, symbol, imageUrl = "image_url"
    }
    public init(ownerId: String = "me", starsCost: Int = 0, collectible: Bool = false,
                slug: String? = nil, name: String? = nil, number: String? = nil,
                model: String? = nil, backdrop: String? = nil, symbol: String? = nil, imageUrl: String? = nil) {
        self.ownerId = ownerId; self.starsCost = starsCost; self.collectible = collectible
        self.slug = slug; self.name = name; self.number = number
        self.model = model; self.backdrop = backdrop; self.symbol = symbol; self.imageUrl = imageUrl
    }
}

public struct UpgradePayload: Encodable {
    public var starsCost: Int = 0; public var model: String?; public var backdrop: String?; public var symbol: String?
    enum CodingKeys: String, CodingKey { case starsCost = "stars_cost", model, backdrop, symbol }
    public init(starsCost: Int = 0, model: String? = nil, backdrop: String? = nil, symbol: String? = nil) {
        self.starsCost = starsCost; self.model = model; self.backdrop = backdrop; self.symbol = symbol
    }
}

public struct UpgradeResult: Codable { public let id: String; public let balance: Int? }

public struct GiftPayload: Encodable {
    public var fromUser: String; public var toUser: String; public var starsCost: Int = 0; public var message: String?
    enum CodingKeys: String, CodingKey { case fromUser = "from_user", toUser = "to_user", starsCost = "stars_cost", message }
    public init(fromUser: String, toUser: String, starsCost: Int = 0, message: String? = nil) {
        self.fromUser = fromUser; self.toUser = toUser; self.starsCost = starsCost; self.message = message
    }
}

public struct GiftResult: Codable {
    public let giftId: String; public let nftId: String; public let ownerId: String; public let fromBalance: Int?
    enum CodingKeys: String, CodingKey {
        case giftId = "gift_id", nftId = "nft_id", ownerId = "owner_id", fromBalance = "from_balance"
    }
}

public struct NFTPatch: Encodable {
    public var name: String?; public var number: String?; public var model: String?
    public var backdrop: String?; public var symbol: String?; public var imageUrl: String?
    enum CodingKeys: String, CodingKey { case name, number, model, backdrop, symbol, imageUrl = "image_url" }
    public init(name: String? = nil, number: String? = nil, model: String? = nil,
                backdrop: String? = nil, symbol: String? = nil, imageUrl: String? = nil) {
        self.name = name; self.number = number; self.model = model
        self.backdrop = backdrop; self.symbol = symbol; self.imageUrl = imageUrl
    }
}

/// Обёртка для кодирования произвольного Encodable (для dict-тел и дженериков).
struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
