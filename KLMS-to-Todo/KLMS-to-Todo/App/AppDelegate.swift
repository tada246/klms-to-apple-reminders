import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemManager: StatusItemManager!
    private var coordinator: SyncCoordinator!
    private var scheduler: SchedulerService!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = SyncCoordinator()
        scheduler = SchedulerService()
        scheduler.coordinator = coordinator
        statusItemManager = StatusItemManager(coordinator: coordinator, onOpenSettings: openSettings)

        let settings = AppSettings()
        if settings.autoSync {
            scheduler.schedule(hour: settings.syncHour, minute: settings.syncMinute)
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView { [weak self] hour, minute, autoSync in
                if autoSync {
                    self?.scheduler.schedule(hour: hour, minute: minute)
                } else {
                    self?.scheduler.cancel()
                }
            }
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "K-LMS 設定"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 380))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItemManager.closePopover()
    }
}
