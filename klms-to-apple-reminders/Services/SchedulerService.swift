import Foundation

class SchedulerService {
    weak var coordinator: SyncCoordinator?
    private var timer: Timer?

    func schedule(interval: SyncInterval, hour: Int, minute: Int, weekday: Int) {
        timer?.invalidate()

        switch interval {
        case .hourly:
            scheduleHourly()
        case .daily:
            scheduleDaily(hour: hour, minute: minute)
        case .weekly:
            scheduleWeekly(weekday: weekday, hour: hour, minute: minute)
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func scheduleHourly() {
        var components = DateComponents()
        components.minute = 0
        components.second = 0
        guard let fireDate = Calendar.current.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) else { return }

        timer = Timer(fire: fireDate, interval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.coordinator?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func scheduleDaily(hour: Int, minute: Int) {
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

    private func scheduleWeekly(weekday: Int, hour: Int, minute: Int) {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        guard let fireDate = Calendar.current.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) else { return }

        timer = Timer(fire: fireDate, interval: 604800, repeats: true) { [weak self] _ in
            Task { await self?.coordinator?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
