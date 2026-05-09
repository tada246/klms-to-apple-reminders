import Foundation
import SwiftUI

enum SyncInterval: String, CaseIterable {
    case hourly = "hourly"
    case daily  = "daily"
    case weekly = "weekly"

    var label: String {
        switch self {
        case .hourly: return "毎時間"
        case .daily:  return "毎日"
        case .weekly: return "毎週"
        }
    }
}

struct AppSettings {
    @AppStorage("listName")      var listName: String = "慶應課題"
    @AppStorage("daysAhead")     var daysAhead: Int = 30
    @AppStorage("syncInterval")  var syncIntervalRaw: String = SyncInterval.daily.rawValue
    @AppStorage("syncHour")      var syncHour: Int = 8
    @AppStorage("syncMinute")    var syncMinute: Int = 0
    @AppStorage("syncWeekday")   var syncWeekday: Int = 2  // 月曜日
    @AppStorage("autoSync")      var autoSync: Bool = true
    @AppStorage("launchAtLogin")            var launchAtLogin: Bool = true
    @AppStorage("hasCompletedOnboarding")   var hasCompletedOnboarding: Bool = false

    var syncInterval: SyncInterval {
        SyncInterval(rawValue: syncIntervalRaw) ?? .daily
    }
}
