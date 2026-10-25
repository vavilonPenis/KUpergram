import Foundation

/// Конфигурация подключения к backend KUpergram.
/// ВНИМАНИЕ: значения-плейсхолдеры. В CI этот файл ПЕРЕЗАПИСЫВАЕТСЯ из секретов
/// (KUPERGRAM_BASE_URL / KUPERGRAM_TOKEN_ME / KUPERGRAM_ADMIN_TOKEN), поэтому
/// реальные токены в публичный исходник не попадают.
public enum KUpergramConfig {
    public static let baseURL = "https://kupergram.kuperov.top"
    public static let userToken = "PLACEHOLDER_USER_TOKEN"
    public static let adminToken = "" // пусто = нет админ-прав (сборка friend)
    public static let currentUserId = "me"
}
