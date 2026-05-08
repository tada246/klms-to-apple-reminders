import SwiftUI

@main
struct KLMSToTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メニューバーアプリのためWindowGroupは使わない
        // 設定ウィンドウはAppDelegateから手動管理
        Settings {
            EmptyView()
        }
    }
}
