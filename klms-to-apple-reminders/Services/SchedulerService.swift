import Foundation

class SchedulerService {
    weak var coordinator: SyncCoordinator?
    private var timer: Timer?

    func schedule(hour: Int, minute: Int) {
        timer?.invalidate()
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let fireDate = Calendar.current.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) else { return }

        timer = Timer(fire: fireDate, interval: 86400, repeats: true) { [weak self] _ in
            Task { await self?.coordinator?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
