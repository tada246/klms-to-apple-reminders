import SwiftUI
import EventKit
import ServiceManagement

private let weekdayLabels: [(Int, String)] = [
    (1, "日曜日"), (2, "月曜日"), (3, "火曜日"), (4, "水曜日"),
    (5, "木曜日"), (6, "金曜日"), (7, "土曜日")
]

struct OnboardingView: View {
    @State private var step: Int = 1
    @State private var remindersStatus: RemindersStatus = .notDetermined
    @State private var store = EKEventStore()

    @AppStorage("listName")               private var listName: String = "慶應課題"
    @AppStorage("syncInterval")           private var syncIntervalRaw: String = SyncInterval.daily.rawValue
    @AppStorage("syncHour")               private var syncHour: Int = 8
    @AppStorage("syncMinute")             private var syncMinute: Int = 0
    @AppStorage("syncWeekday")            private var syncWeekday: Int = 2
    @AppStorage("autoSync")               private var autoSync: Bool = true
    @AppStorage("launchAtLogin")          private var launchAtLogin: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    /// 完了時に呼ばれる（AppDelegate がログインウィンドウを開く）
    var onComplete: (() -> Void)?

    enum RemindersStatus { case notDetermined, granted, denied }
    private var syncInterval: SyncInterval { SyncInterval(rawValue: syncIntervalRaw) ?? .daily }

    var body: some View {
        VStack(spacing: 0) {
            // ステップドット（2 ステップ）
            HStack(spacing: 6) {
                ForEach(1...2, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut, value: step)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // アイコン＋タイトル
            VStack(spacing: 6) {
                Image(systemName: headerIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(headerTitle)
                    .font(.headline)
            }
            .padding(.bottom, 16)

            Divider()

            Group {
                switch step {
                case 1: stepOne
                default: stepTwo
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // フッター
            HStack {
                if step > 1 {
                    Button("← 戻る") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Spacer()
                if step < 2 {
                    Button("次へ →") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canProceed)
                } else {
                    Button("K-LMS にログイン →") { complete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 400)
        .onAppear { syncRemindersStatus() }
    }

    // MARK: - Header

    private var headerIcon: String {
        step == 1 ? "checklist" : "gearshape.fill"
    }

    private var headerTitle: String {
        step == 1 ? "リマインダーへのアクセス" : "設定を確認"
    }

    // MARK: - Step 1: リマインダー権限

    private var stepOne: some View {
        VStack(spacing: 14) {
            Text("K-LMSの課題をAppleリマインダーに自動追加します。\nリマインダーへのアクセスが必要です。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            switch remindersStatus {
            case .notDetermined:
                Button {
                    Task { await requestRemindersAccess() }
                } label: {
                    Label("アクセスを許可する", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .granted:
                Label("アクセスが許可されました", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

            case .denied:
                VStack(spacing: 10) {
                    Label("アクセスが拒否されています", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("システム設定 › プライバシーとセキュリティ › リマインダー で許可してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button("システム設定を開く") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                            )
                        }
                        .buttonStyle(.bordered)
                        Button("再確認") { Task { await requestRemindersAccess() } }
                            .buttonStyle(.plain).foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: 設定確認

    private var stepTwo: some View {
        VStack(spacing: 0) {
            row("保存先リスト名") {
                TextField("", text: $listName)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            Divider().padding(.horizontal, -24)

            row("自動同期") {
                Toggle("", isOn: $autoSync).labelsHidden()
            }
            Divider().padding(.horizontal, -24)

            if autoSync {
                row("タイミング") {
                    Picker("", selection: $syncIntervalRaw) {
                        ForEach(SyncInterval.allCases, id: \.rawValue) {
                            Text($0.label).tag($0.rawValue)
                        }
                    }
                    .frame(width: 85)
                }
                Divider().padding(.horizontal, -24)

                if syncInterval == .weekly {
                    row("曜日") {
                        Picker("", selection: $syncWeekday) {
                            ForEach(weekdayLabels, id: \.0) { d, l in Text(l).tag(d) }
                        }
                        .frame(width: 85)
                    }
                    Divider().padding(.horizontal, -24)
                }

                if syncInterval != .hourly {
                    row("時刻") {
                        HStack(spacing: 2) {
                            Picker("", selection: $syncHour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                            }.frame(width: 52)
                            Text(":").foregroundColor(.secondary)
                            Picker("", selection: $syncMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)) }
                            }.frame(width: 52)
                        }
                    }
                    Divider().padding(.horizontal, -24)
                }
            }

            row("ログイン時に自動起動") {
                Toggle("", isOn: $launchAtLogin).labelsHidden()
                    .onChange(of: launchAtLogin) { enabled in
                        if #available(macOS 13.0, *) {
                            if enabled { try? SMAppService.mainApp.register() }
                            else        { try? SMAppService.mainApp.unregister() }
                        }
                    }
            }

            Spacer()

            Text("次の画面でK-LMSにログインすると設定が完了します。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            content()
        }
        .padding(.vertical, 9)
    }

    // MARK: - Logic

    private var canProceed: Bool {
        step == 1 ? remindersStatus == .granted : true
    }

    private func complete() {
        hasCompletedOnboarding = true
        onComplete?()
    }

    private func syncRemindersStatus() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:          remindersStatus = .granted
            case .denied, .restricted: remindersStatus = .denied
            default:                   remindersStatus = .notDetermined
            }
        } else {
            switch status {
            case .authorized:          remindersStatus = .granted
            case .denied, .restricted: remindersStatus = .denied
            default:                   remindersStatus = .notDetermined
            }
        }
    }

    @MainActor
    private func requestRemindersAccess() async {
        do {
            if #available(macOS 14.0, *) {
                let granted = try await store.requestFullAccessToReminders()
                remindersStatus = granted ? .granted : .denied
            } else {
                let granted = await withCheckedContinuation { cont in
                    store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
                }
                remindersStatus = granted ? .granted : .denied
            }
        } catch {
            remindersStatus = .denied
        }
    }
}
