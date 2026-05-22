import SwiftUI
import ServiceManagement

private let weekdayLabels: [(Int, String)] = [
    (1, "日曜日"), (2, "月曜日"), (3, "火曜日"), (4, "水曜日"),
    (5, "木曜日"), (6, "金曜日"), (7, "土曜日")
]

struct SettingsView: View {
    @AppStorage("listName")      private var listName: String = "慶應課題"
    @AppStorage("daysAhead")     private var daysAhead: Int = 30
    @AppStorage("syncInterval")  private var syncIntervalRaw: String = SyncInterval.daily.rawValue
    @AppStorage("syncHour")      private var syncHour: Int = 8
    @AppStorage("syncMinute")    private var syncMinute: Int = 0
    @AppStorage("syncWeekday")   private var syncWeekday: Int = 2
    @AppStorage("autoSync")      private var autoSync: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = true

    var onScheduleChanged: (() -> Void)?

    private var syncInterval: SyncInterval {
        SyncInterval(rawValue: syncIntervalRaw) ?? .daily
    }

    var body: some View {
        Form {
            // MARK: リマインダー設定
            Section {
                LabeledContent("保存先リスト名") {
                    TextField("", text: $listName)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                }
                LabeledContent("取得日数") {
                    Stepper("\(daysAhead)日先まで", value: $daysAhead, in: 1...90)
                }
            } header: {
                Text("リマインダー設定")
            } footer: {
                Text("リストが存在しない場合は自動作成されます。")
                    .font(.caption).foregroundColor(.secondary)
            }

            // MARK: 自動同期
            Section("自動同期") {
                Toggle("自動同期を有効にする", isOn: $autoSync)

                if autoSync {
                    LabeledContent("同期タイミング") {
                        Picker("", selection: $syncIntervalRaw) {
                            ForEach(SyncInterval.allCases, id: \.rawValue) { interval in
                                Text(interval.label).tag(interval.rawValue)
                            }
                        }
                        .frame(width: 100)
                    }

                    if syncInterval == .weekly {
                        LabeledContent("曜日") {
                            Picker("", selection: $syncWeekday) {
                                ForEach(weekdayLabels, id: \.0) { day, label in
                                    Text(label).tag(day)
                                }
                            }
                            .frame(width: 100)
                        }
                    }

                    if syncInterval == .daily || syncInterval == .weekly {
                        LabeledContent("同期時刻") {
                            HStack(spacing: 4) {
                                Picker("", selection: $syncHour) {
                                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                                }
                                .frame(width: 60)
                                Text("時")
                                Picker("", selection: $syncMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)) }
                                }
                                .frame(width: 60)
                                Text("分")
                            }
                        }
                    }
                }

                Toggle("ログイン時に自動起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        if #available(macOS 13.0, *) {
                            if enabled { try? SMAppService.mainApp.register() }
                            else        { try? SMAppService.mainApp.unregister() }
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onChange(of: autoSync)        { _ in onScheduleChanged?() }
        .onChange(of: syncIntervalRaw) { _ in onScheduleChanged?() }
        .onChange(of: syncHour)        { _ in onScheduleChanged?() }
        .onChange(of: syncMinute)      { _ in onScheduleChanged?() }
        .onChange(of: syncWeekday)     { _ in onScheduleChanged?() }
    }
}
