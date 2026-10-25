import SwiftUI

/// Экран Stars: баланс + история начислений и списаний (визуальная экономика).
public struct StarsView: View {
    @ObservedObject var store: KUpergramStore
    public init(store: KUpergramStore) { self.store = store }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 56)).foregroundStyle(KTheme.star)
                        Text("\(store.myBalance)")
                            .font(.system(size: 44, weight: .bold)).monospacedDigit()
                        Text("Баланс · \(store.name(of: store.currentUserId))")
                            .foregroundStyle(.secondary)
                        VisualBadge()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("История") {
                    if myHistory.isEmpty {
                        Text("Пока нет операций").foregroundStyle(.secondary)
                    } else {
                        ForEach(myHistory) { entry in
                            HStack {
                                Image(systemName: entry.delta >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                    .foregroundStyle(entry.delta >= 0 ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.reason ?? (entry.delta >= 0 ? "Начисление" : "Списание"))
                                    Text(entry.date, style: .date)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.delta >= 0 ? "+" : "")\(entry.delta)")
                                    .font(.body.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(entry.delta >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stars")
            .overlay(alignment: .top) { ErrorBanner(message: $store.lastError) }
            .refreshable { await store.sync() }
            .task { await store.sync() }
        }
    }

    private var myHistory: [StarsEntry] {
        store.history.filter { $0.userId == store.currentUserId }
    }
}
