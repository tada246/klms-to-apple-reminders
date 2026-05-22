import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemManager:  StatusItemManager!
    private var coordinator:        SyncCoordinator!
    private var scheduler:          SchedulerService!
    private var settingsWindow:     NSWindow?
    private var onboardingWindow:   NSWindow?
    private var loginController:    CanvasLoginWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = SyncCoordinator()
        scheduler   = SchedulerService()
        scheduler.coordinator = coordinator

        statusItemManager = StatusItemManager(
            coordinator:    coordinator,
            onOpenSettings: openSettings,
            onRelogin:      { [weak self] in self?.showLogin(isRelogin: true) }
        )

        // セッション切れ通知 → ログインウィンドウを自動表示
        coordinator.onSessionExpired = { [weak self] in
            self?.showLogin(isRelogin: true)
        }

        let settings = AppSettings()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        } else {
            startServices(settings: settings)
            // 起動時にトークンがなければ（初回ログイン未完了）ログインを促す
            if coordinator.isSessionExpired {
                showLogin(isRelogin: false)
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.startServices(settings: AppSettings())
            // 設定完了後に K-LMS ログインウィンドウを表示
            self?.showLogin(isRelogin: false)
        }

        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title = "K-LMS → Reminders"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Login

    /// WKWebView ログインウィンドウを表示する。
    /// - Parameter isRelogin: true = 再ログイン（既存セッション切れ）、false = 初回
    private func showLogin(isRelogin: Bool) {
        // 既にログインウィンドウが開いている場合は前面に出すだけ
        if let existing = loginController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = CanvasLoginWindowController.present()

        controller.onSuccess = { [weak self] in
            self?.loginController = nil
            Task { @MainActor [weak self] in
                self?.coordinator.notifyLoginSuccess()
            }
        }

        controller.onDismiss = { [weak self] in
            self?.loginController = nil
            // ウィンドウを閉じてもセッション切れ状態のまま → メニューに再ログインボタン残る
        }

        loginController = controller
    }

    // MARK: - Services

    private func startServices(settings: AppSettings) {
        if settings.launchAtLogin, #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
        if settings.autoSync {
            scheduler.schedule(
                interval: settings.syncInterval,
                hour:     settings.syncHour,
                minute:   settings.syncMinute,
                weekday:  settings.syncWeekday
            )
        }
    }

    // MARK: - Settings

    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onScheduleChanged: { [weak self] in
                let s = AppSettings()
                if s.autoSync {
                    self?.scheduler.schedule(
                        interval: s.syncInterval,
                        hour:     s.syncHour,
                        minute:   s.syncMinute,
                        weekday:  s.syncWeekday
                    )
                } else {
                    self?.scheduler.cancel()
                }
            })
            let hosting = NSHostingController(rootView: view)
            let window  = NSWindow(contentViewController: hosting)
            window.title = "K-LMS 設定"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 440, height: 360))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItemManager.closePopover()
    }
}
