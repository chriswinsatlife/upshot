import Foundation

extension UpshotPreferences {
    static let historyRetentionDaysKey = "historyRetentionDays"

    static var historyRetentionDays: Int {
        get { max(0, UpshotStorage.defaults.integer(forKey: historyRetentionDaysKey)) }
        set { UpshotStorage.defaults.set(max(0, newValue), forKey: historyRetentionDaysKey) }
    }
}
