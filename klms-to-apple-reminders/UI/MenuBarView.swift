import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: SyncCoordinator
    var onOpenSettings: () -> Void
    var onRelogin:      () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            actions
        }
        .frame(width: 260)
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
                .foregroundColor(.accentColor)
            Text("K-LMS → Reminders")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 前回ログイン日時
            if let date = coordinator.lastLoginDate {
                HStack(spacing: 4) {
                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("前回ログイン: \(formattedLoginDate(date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 同期状態
            if coordinator.isSyncing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("同期中...").font(.caption).foregroundColor(.secondary)
                }
            } else if coordinator.isSessionExpired {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("セッションが切れています。再ログインが必要です。")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let error = coordinator.lastError {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let result = coordinator.lastResult {
                Text("最終同期: \(result.formattedTime)")
                    .font(.caption).foregroundColor(.secondary)
                Text(result.summary)
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                Text("未同期").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            menuButton(title: "今すぐ同期", icon: "arrow.clockwise") {
                Task { await coordinator.sync() }
            }
            .disabled(coordinator.isSyncing || coordinator.isSessionExpired)

            menuButton(title: "設定...", icon: "gearshape") {
                onOpenSettings()
            }

            Divider().padding(.vertical, 2)

            // セッション切れのときだけ「再ログイン」ボタンを表示
            if coordinator.isSessionExpired {
                menuButton(title: "再ログイン", icon: "arrow.right.circle.fill",
                           foregroundColor: .orange) {
                    onRelogin()
                }
            }

            menuButton(title: "終了", icon: "power", foregroundColor: .red) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    private func menuButton(
        title: String,
        icon: String,
        foregroundColor: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .hoverBackground()
    }

    private func formattedLoginDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今日 \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨日 \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Hover background

private extension View {
    func hoverBackground() -> some View {
        self.modifier(HoverBackgroundModifier())
    }
}

private struct HoverBackgroundModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .onHover { isHovered = $0 }
    }
}
