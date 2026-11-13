import Foundation

extension UpshotPreferences {
    static let historyRetentionDaysKey = "historyRetentionDays"

    static var historyRetentionDays: Int {
        get { max(0, UserDefaults.standard.integer(forKey: historyRetentionDaysKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: historyRetentionDaysKey) }
    }
}
