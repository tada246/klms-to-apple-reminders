import Foundation
import SwiftUI

struct AppSettings {
    @AppStorage("listName")   var listName: String = "慶應課題"
    @AppStorage("daysAhead")  var daysAhead: Int = 30
    @AppStorage("syncHour")   var syncHour: Int = 8
    @AppStorage("syncMinute") var syncMinute: Int = 0
    @AppStorage("autoSync")   var autoSync: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}
