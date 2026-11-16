import Foundation
import SwiftData
import UIKit

@MainActor final class ReadingClock {
    let context: ModelContext
    var timer: Timer?
    var previous = Date()
    var lastInteraction = Date()
    var observers: [NSObjectProtocol] = []
    init(context: ModelContext) { self.context = context }
    func start() {
        previous = Date(); lastInteraction = Date()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.previous = Date() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func interact() { lastInteraction = Date() }
    func tick() {
        let now = Date(); defer { previous = now }
        // A page can take time to read; expire an unattended reader after two minutes.
        guard UIApplication.shared.applicationState == .active, now.timeIntervalSince(lastInteraction) < 120 else { return }
        let seconds = min(5, max(0, now.timeIntervalSince(previous)))
        let day = Calendar.current.startOfDay(for: now)
        do {
            let record = try context.fetch(FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.day == day })).first
            if let record { record.seconds += seconds }
            else { context.insert(ReadingDay(day: day, seconds: seconds)) }
            try context.save()
        } catch { /* Reading remains available if statistics storage fails. */ }
    }
    func stop() { tick(); timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
}
