import Foundation

// MARK: - Модели визуальной системы Stars / NFT
//
// ВАЖНО: это косметические сущности приватного форка. Они НЕ являются
// настоящими Telegram Stars или блокчейн-NFT и не выдаются за них.

public struct KUser: Codable, Identifiable, Hashable {
    public let id: String        // "me" | "friend"
    public let name: String
}

public struct GiftCard: Codable, Identifiable, Hashable {
    public let id: String
    public var slug: String?
    public var name: String?
    public var number: String?
    public var model: String?
    public var backdrop: String?
    public var symbol: String?
    public var imageUrl: String?
    public var ownerId: String
    public var addedAt: Int
    public var collectibleFlag: Int?   // is_collectible (0/1) с сервера

    enum CodingKeys: String, CodingKey {
        case id, slug, name, number, model, backdrop, symbol
        case imageUrl = "image_url"
        case ownerId = "owner_id"
        case addedAt = "added_at"
        case collectibleFlag = "is_collectible"
    }

    public var title: String { name ?? slug ?? "Unknown gift" }
    public var addedDate: Date { Date(timeIntervalSince1970: TimeInterval(addedAt)) }
}

public struct StarsEntry: Codable, Identifiable, Hashable {
    public let id: String
    public let userId: String
    public let delta: Int
    public let balance: Int
    public let reason: String?
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id, delta, balance, reason
        case userId = "user_id"
        case createdAt = "created_at"
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }
}

/// Событие дарения подарка (как в оригинале: подарок «уехал» к другому юзеру).
public struct GiftEvent: Codable, Identifiable, Hashable {
    public let id: String
    public let nftId: String
    public let fromUser: String
    public let toUser: String
    public let starsCost: Int
    public let message: String?
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id, message
        case nftId = "nft_id"
        case fromUser = "from_user"
        case toUser = "to_user"
        case starsCost = "stars_cost"
        case createdAt = "created_at"
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }
}

/// Полный снимок состояния с сервера синхронизации.
public struct SyncState: Codable {
    public let users: [KUser]
    public let stars: [String: Int]
    public let nfts: [GiftCard]
    public let history: [StarsEntry]
    public let gifts: [GiftEvent]
}

/// Поля, которые резолвер вернул по slug (с публичного источника либо пусто).
public struct ResolvedSlug: Codable {
    public var slug: String
    public var name: String?
    public var number: String?
    public var model: String?
    public var backdrop: String?
    public var symbol: String?
    public var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case slug, name, number, model, backdrop, symbol
        case imageUrl = "image_url"
    }
}
