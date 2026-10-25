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
            AdminPanelView(store: store)
                .tabItem { Label("Админ", systemImage: "gearshape.fill") }
        }
        .tint(KTheme.tgBlue)
        .task { await store.sync() }
    }
}

/// Мост для встраивания SwiftUI-раздела в UIKit-навигацию Telegram-форка.
public enum KUpergramHost {
    /// Собирает готовый UIViewController.
    /// - Parameters:
    ///   - baseURL: адрес сервера синхронизации (например, https://kupergram.example.com)
    ///   - adminToken: приватный токен (храни в Keychain, НЕ в исходниках)
    ///   - currentUserId: "me" или "friend" — кто на этом устройстве
    @MainActor
    public static func makeViewController(baseURL: URL,
                                          adminToken: String,
                                          currentUserId: String) -> UIViewController {
        let api = KUpergramAPI(config: .init(baseURL: baseURL, adminToken: adminToken))
        let store = KUpergramStore(api: api, currentUserId: currentUserId)
        let root = KUpergramRootView(store: store)
        let vc = UIHostingController(rootView: root)
        vc.title = "KUpergram"
        return vc
    }
}
