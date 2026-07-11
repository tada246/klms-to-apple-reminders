import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemManager:  StatusItemManager!
    private var coordinator:        SyncCoordinator!
    private var scheduler:          SchedulerService!
    private var settingsWindow:     NSWindow?
    private var onboardingWindow:   NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = SyncCoordinator()
        scheduler   = SchedulerService()
        scheduler.coordinator = coordinator

        statusItemManager = StatusItemManager(
            coordinator:    coordinator,
            onOpenSettings: openSettings
        )

        // フィード URL 未設定 → 設定ウィンドウを自動表示
        coordinator.onNeedsConfiguration = { [weak self] in
            self?.openSettings()
        }

        let settings = AppSettings()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        } else {
            startServices(settings: settings)
            // 起動時にフィード URL が未設定なら設定画面を開いて貼り付けを促す
            if !coordinator.isConfigured {
                openSettings()
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.startServices(settings: AppSettings())
            // 設定完了後にフィード URL 貼り付けを促すため設定画面を表示
            self?.openSettings()
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
            }, onFeedURLSaved: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.coordinator.notifyConfigured()
                }
            }, onSyncNow: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.coordinator.sync()
                }
            })
            let hosting = NSHostingController(rootView: view)
            let window  = NSWindow(contentViewController: hosting)
            window.title = "K-LMS 設定"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 440, height: 420))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItemManager.closePopover()
    }
}
