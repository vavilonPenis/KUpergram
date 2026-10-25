import Foundation
import UIKit
import SwiftUI

// Минимальная первая версия раздела KUpergram внутри форка Telegram.
// Цель — проверить весь путь интеграции (кнопка → экран → backend).
// Полный UI (Stars/NFT/магазин/дарение) переносится вторым шагом.
//
// Визуальные Stars/NFT — косметическая экономика форка, НЕ настоящие Telegram-активы.

// MARK: - минимальные модели ответа /state
struct KGState: Decodable {
    let stars: [String: Int]
    let nfts: [KGGift]
}

struct KGGift: Decodable, Identifiable {
    let id: String
    let name: String?
    let slug: String?
    let ownerId: String
    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case ownerId = "owner_id"
    }
    var title: String { name ?? slug ?? "Gift" }
}

// MARK: - сетевой клиент (минимум)
final class KGClient {
    static func fetchState() async throws -> KGState {
        guard let url = URL(string: KUpergramConfig.baseURL)?.appendingPathComponent("state") else {
            throw NSError(domain: "KG", code: -1)
        }
        var req = URLRequest(url: url)
        req.setValue(KUpergramConfig.userToken, forHTTPHeaderField: "X-User-Token")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw NSError(domain: "KG", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return try JSONDecoder().decode(KGState.self, from: data)
    }
}

// MARK: - минимальный экран
@available(iOS 16.0, *)
struct KUpergramMinimalView: View {
    @State private var balance: Int = 0
    @State private var gifts: [KGGift] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("Баланс")
                    Spacer()
                    Text("\(balance)").bold().monospacedDigit()
                }
                Text("Визуальный · KUpergram")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Мои подарки (\(myGifts.count))") {
                if loading {
                    HStack { ProgressView(); Text("Загрузка…") }
                } else if myGifts.isEmpty {
                    Text("Пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(myGifts) { g in
                        HStack {
                            Image(systemName: "gift.fill").foregroundStyle(.blue)
                            Text(g.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("KUpergram")
        .task { await load() }
        .refreshable { await load() }
    }

    private var myGifts: [KGGift] {
        gifts.filter { $0.ownerId == KUpergramConfig.currentUserId }
    }

    private func load() async {
        loading = true
        do {
            let s = try await KGClient.fetchState()
            balance = s.stars[KUpergramConfig.currentUserId] ?? 0
            gifts = s.nfts
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - точка входа (возвращает UIViewController для встраивания)
public enum KUpergramEntry {
    @MainActor
    public static func makeViewController() -> UIViewController {
        if #available(iOS 16.0, *) {
            return UIHostingController(rootView: KUpergramMinimalView())
        } else {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "KUpergram требует iOS 16+"
            label.textAlignment = .center
            label.frame = vc.view.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            vc.view.addSubview(label)
            return vc
        }
    }
}
