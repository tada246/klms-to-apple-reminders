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

    @State private var feedURLInput: String = KeychainHelper.loadFeedURL() ?? ""
    @State private var feedURLError: String?
    @State private var feedURLSaved: Bool = false

    var onScheduleChanged: (() -> Void)?
    var onFeedURLSaved:    (() -> Void)?
    var onSyncNow:         (() -> Void)?

    private var syncInterval: SyncInterval {
        SyncInterval(rawValue: syncIntervalRaw) ?? .daily
    }

    private var isConfigured: Bool {
        KeychainHelper.loadFeedURL() != nil
    }

    var body: some View {
        Form {
            // MARK: Canvas カレンダーフィード
            Section {
                TextField("https://lms.keio.jp/feeds/calendars/xxxxx.ics", text: $feedURLInput)
                    .textFieldStyle(.roundedBorder)

                if let error = feedURLError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if feedURLSaved {
                    Label("保存しました", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                HStack {
                    Button("保存") { saveFeedURL() }
                        .disabled(feedURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isConfigured, let onSyncNow {
                        Button("今すぐ同期") { onSyncNow() }
                    }
                }
            } header: {
                Text("Canvas カレンダーフィード")
            } footer: {
                Text("Canvas → カレンダー → 左下の「カレンダーフィード」の URL をコピーして貼り付けてください。")
                    .font(.caption).foregroundColor(.secondary)
            }

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
        .onChange(of: feedURLInput)    { _ in feedURLSaved = false }
    }

    // MARK: - Feed URL

    private func saveFeedURL() {
        let trimmed = feedURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"), trimmed.contains(".ics") else {
            feedURLError = "有効な .ics フィード URL を入力してください（https:// で始まる URL）。"
            feedURLSaved = false
            return
        }

        do {
            try KeychainHelper.saveFeedURL(trimmed)
            feedURLError = nil
            feedURLSaved = true
            onFeedURLSaved?()
        } catch {
            feedURLError = error.localizedDescription
            feedURLSaved = false
        }
    }
}
