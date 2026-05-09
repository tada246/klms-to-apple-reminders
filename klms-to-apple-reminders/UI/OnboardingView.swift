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
    @State private var token: String = ""
    @State private var showToken = false
    @State private var tokenSaveWork: DispatchWorkItem?

    @AppStorage("listName")               private var listName: String = "慶應課題"
    @AppStorage("syncInterval")           private var syncIntervalRaw: String = SyncInterval.daily.rawValue
    @AppStorage("syncHour")               private var syncHour: Int = 8
    @AppStorage("syncMinute")             private var syncMinute: Int = 0
    @AppStorage("syncWeekday")            private var syncWeekday: Int = 2
    @AppStorage("autoSync")               private var autoSync: Bool = true
    @AppStorage("launchAtLogin")          private var launchAtLogin: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var onComplete: (() -> Void)?

    enum RemindersStatus { case notDetermined, granted, denied }
    private var syncInterval: SyncInterval { SyncInterval(rawValue: syncIntervalRaw) ?? .daily }

    var body: some View {
        VStack(spacing: 0) {
            // ステップドット
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
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

            // コンテンツ
            Group {
                switch step {
                case 1: stepOne
                case 2: stepTwo
                default: stepThree
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
                if step < 3 {
                    Button("次へ →") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canProceed)
                } else {
                    Button("はじめる") { complete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 420)
        .onAppear { syncRemindersStatus() }
    }

    // MARK: - Header

    private var headerIcon: String {
        switch step {
        case 1: return "checklist"
        case 2: return "key.fill"
        default: return "checkmark.seal.fill"
        }
    }

    private var headerTitle: String {
        switch step {
        case 1: return "リマインダーへのアクセス"
        case 2: return "K-LMS APIトークン"
        default: return "設定を確認"
        }
    }

    // MARK: - Step 1

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
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                        }
                        .buttonStyle(.bordered)
                        Button("再確認") { Task { await requestRemindersAccess() } }
                            .buttonStyle(.plain).foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Step 2

    private var tokenValidationMessage: String? {
        if token.isEmpty { return nil }
        if !TokenValidator.isValid(token) { return TokenValidator.invalidMessage }
        return nil
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 10) {
            // トークン入力欄
            HStack(spacing: 6) {
                Group {
                    if showToken {
                        TextField("トークンを貼り付け", text: $token)
                    } else {
                        SecureField("トークンを貼り付け", text: $token)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button(showToken ? "隠す" : "表示") { showToken.toggle() }
                    .buttonStyle(.plain).foregroundColor(.accentColor).font(.caption)
            }
            .onChange(of: token) { newValue in
                tokenSaveWork?.cancel()
                guard !newValue.isEmpty, TokenValidator.isValid(newValue) else { return }
                let work = DispatchWorkItem { try? KeychainHelper.save(newValue) }
                tokenSaveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
            }

            // バリデーションメッセージ
            if let msg = tokenValidationMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
            } else if token.isEmpty {
                Label("トークンを入力してください", systemImage: "info.circle")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Label("Keychainに自動保存されます", systemImage: "lock.fill")
                    .font(.caption).foregroundColor(.secondary)
            }

            Divider()

            // 取得手順
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("取得方法")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    Spacer()
                    Link("K-LMSを開く →", destination: URL(string: "https://lms.keio.jp/profile/settings")!)
                        .font(.caption)
                }

                ForEach(tokenSteps, id: \.0) { num, text in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(num).")
                            .font(.caption).foregroundColor(.accentColor)
                            .frame(width: 14, alignment: .trailing)
                        Text(text)
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private let tokenSteps: [(Int, String)] = [
        (1, "「承認済みのアプリケーション」セクションを探す"),
        (2, "「新しいアクセストークン」をクリック"),
        (3, "目的に「KLMS to Apple リマインダー」と入力"),
        (4, "有効期限は空白のまま（または任意の期間）"),
        (5, "「トークンの生成」をクリックし、表示されたトークンをコピー"),
        (6, "⚠️ 画面を閉じると再表示不可。必ずコピーしてから閉じること"),
    ]

    // MARK: - Step 3

    private var stepThree: some View {
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
                        ForEach(SyncInterval.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
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
                            else { try? SMAppService.mainApp.unregister() }
                        }
                    }
            }
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
        switch step {
        case 1: return remindersStatus == .granted
        case 2: return TokenValidator.isValid(token)
        default: return true
        }
    }

    private func complete() {
        tokenSaveWork?.cancel()
        if !token.isEmpty { try? KeychainHelper.save(token) }
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
