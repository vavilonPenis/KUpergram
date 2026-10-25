import SwiftUI
import UIKit

/// Корневой экран KUpergram-расширения. Встраивается в форк Telegram через
/// `KUpergramHost.makeViewController(...)` и показывается как отдельный раздел.
public struct KUpergramRootView: View {
    @StateObject private var store: KUpergramStore

    public init(store: KUpergramStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        TabView {
            GiftsView(store: store)
                .tabItem { Label("Gifts", systemImage: "gift.fill") }
            ShopView(store: store)
                .tabItem { Label("Магазин", systemImage: "bag.fill") }
            StarsView(store: store)
                .tabItem { Label("Stars", systemImage: "star.fill") }
            GiftHistoryView(store: store)
                .tabItem { Label("История", systemImage: "clock.fill") }
            // Админ-панель — только на устройстве с админ-правами (me). У friend её нет.
            if store.isAdmin {
                AdminPanelView(store: store)
                    .tabItem { Label("Админ", systemImage: "gearshape.fill") }
            }
        }
        .tint(KTheme.tgBlue)
        .task { await store.sync() }
    }
}

/// Мост для встраивания SwiftUI-раздела в UIKit-навигацию Telegram-форка.
public enum KUpergramHost {
    /// Собирает готовый UIViewController.
    /// - Parameters:
    ///   - baseURL: адрес сервера синхронизации (например, https://kupergram.kuperov.top)
    ///   - userToken: пользовательский токен (me или friend) — личность определит сервер
    ///   - adminToken: админ-токен; передавать ТОЛЬКО на устройстве «me». Для friend — nil.
    ///   - currentUserId: "me" или "friend" (для фильтров UI; доступ всё равно решает токен)
    ///   Токены храни в Keychain, НЕ в исходниках.
    @MainActor
    public static func makeViewController(baseURL: URL,
                                          userToken: String,
                                          adminToken: String? = nil,
                                          currentUserId: String) -> UIViewController {
        let config = KUpergramAPI.Config(baseURL: baseURL, userToken: userToken, adminToken: adminToken)
        let api = KUpergramAPI(config: config)
        let store = KUpergramStore(api: api, currentUserId: currentUserId, isAdmin: config.isAdmin)
        let root = KUpergramRootView(store: store)
        let vc = UIHostingController(rootView: root)
        vc.title = "KUpergram"
        return vc
    }
}
