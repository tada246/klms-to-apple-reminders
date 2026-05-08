import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var token: String = ""
    @State private var showToken = false
    @State private var saveMessage: String?
    @AppStorage("listName")    private var listName: String = "慶應課題"
    @AppStorage("daysAhead")   private var daysAhead: Int = 30
    @AppStorage("syncHour")    private var syncHour: Int = 8
    @AppStorage("syncMinute")  private var syncMinute: Int = 0
    @AppStorage("autoSync")    private var autoSync: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var onSave: ((Int, Int, Bool) -> Void)?

    var body: some View {
        Form {
            Section("K-LMS APIトークン") {
                HStack {
                    if showToken {
                        TextField("トークンを入力", text: $token)
                    } else {
                        SecureField("トークンを入力", text: $token)
                    }
                    Button(showToken ? "隠す" : "表示") { showToken.toggle() }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
                Link("トークンを発行する →", destination: URL(string: "https://lms.keio.jp/profile/settings")!)
                    .font(.caption)
                Button("トークンを削除", role: .destructive) {
                    KeychainHelper.delete()
                    token = ""
                }
                .font(.caption)
            }

            Section("リマインダー設定") {
                LabeledContent("リスト名") {
                    TextField("慶應課題", text: $listName)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                }
                LabeledContent("取得日数") {
                    Stepper("\(daysAhead)日先まで", value: $daysAhead, in: 1...90)
                }
            }

            Section("自動同期") {
                Toggle("自動同期を有効にする", isOn: $autoSync)
                if autoSync {
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
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        if #available(macOS 13.0, *) {
                            if enabled {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                    }
            }

            HStack {
                if let msg = saveMessage {
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onAppear {
            token = KeychainHelper.load() ?? ""
        }
    }

    private func save() {
        if !token.isEmpty {
            try? KeychainHelper.save(token)
        }
        onSave?(syncHour, syncMinute, autoSync)
        saveMessage = "保存しました ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveMessage = nil
        }
    }
}
