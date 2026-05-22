import AppKit
import SwiftUI

class StatusItemManager {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellable: Any?

    init(coordinator: SyncCoordinator,
         onOpenSettings: @escaping () -> Void,
         onRelogin: @escaping () -> Void) {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                coordinator:    coordinator,
                onOpenSettings: onOpenSettings,
                onRelogin:      onRelogin
            )
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "K-LMS")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // coordinator の状態変化に応じてアイコンを更新
        cancellable = coordinator.objectWillChange.sink { [weak self, weak coordinator] _ in
            DispatchQueue.main.async {
                self?.updateIcon(
                    syncing:        coordinator?.isSyncing        ?? false,
                    sessionExpired: coordinator?.isSessionExpired ?? false,
                    hasError:       coordinator?.lastError != nil
                )
            }
        }
    }

    func updateIcon(syncing: Bool, sessionExpired: Bool, hasError: Bool) {
        let name: String
        if syncing          { name = "arrow.clockwise" }
        else if sessionExpired { name = "lock.open.fill" }
        else if hasError    { name = "exclamationmark.circle" }
        else                { name = "checklist" }
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "K-LMS")
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
