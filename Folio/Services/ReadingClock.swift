import Foundation
import SwiftData
import UIKit

struct ReadingSlice: Equatable {
    var day: Date
    var seconds: TimeInterval
}

/// Counts only explicitly active intervals, clipping inactivity and splitting midnight.
struct ReadingSession {
    private(set) var previous: Date?
    private var lastInteraction: Date = .distantPast
    let idleLimit: TimeInterval = 120
    mutating func resume(at date: Date) { previous = date; lastInteraction = date }
    mutating func discardAndPause() { previous = nil }
    mutating func interact(at date: Date, calendar: Calendar = .current) -> [ReadingSlice] {
        let slices = sample(at: date, calendar: calendar)
        if previous == nil { previous = date }
        lastInteraction = date
        return slices
    }
    mutating func pause(at date: Date, calendar: Calendar = .current) -> [ReadingSlice] {
        let slices = sample(at: date, calendar: calendar); previous = nil; return slices
    }
    mutating func sample(at date: Date, calendar: Calendar = .current) -> [ReadingSlice] {
        guard let start = previous else { return [] }
        previous = date
        let end = min(date, lastInteraction.addingTimeInterval(idleLimit))
        guard end > start else { return [] }
        var slices: [ReadingSlice] = [], cursor = start
        while cursor < end {
            let day = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let boundary = min(end, next)
            slices.append(ReadingSlice(day: day, seconds: boundary.timeIntervalSince(cursor)))
            cursor = boundary
        }
        return slices
    }
}

@MainActor final class ReadingClock {
    private let context: ModelContext
    private let isReading: () -> Bool
    private var session = ReadingSession()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    init(context: ModelContext, isReading: @escaping () -> Bool = { true }) {
        self.context = context; self.isReading = isReading
    }
    func start() {
        guard timer == nil else { return }
        if UIApplication.shared.applicationState == .active && isReading() { session.resume(at: Date()) }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.persist(self.session.pause(at: Date())) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.isReading() else { return }; self.session.resume(at: Date()) }
        })
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func interact() {
        guard UIApplication.shared.applicationState == .active, isReading() else { return }
        persist(session.interact(at: Date()))
    }
    func tick() {
        guard UIApplication.shared.applicationState == .active else { session.discardAndPause(); return }
        guard isReading() else { session.discardAndPause(); return }
        if session.previous == nil { session.resume(at: Date()) }
        persist(session.sample(at: Date()))
    }
    func stop() {
        if UIApplication.shared.applicationState == .active, isReading() { persist(session.pause(at: Date())) }
        else { session.discardAndPause() }
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
    }
    private func persist(_ slices: [ReadingSlice]) {
        guard !slices.isEmpty else { return }
        do {
            for slice in slices {
                let day = slice.day
                if let record = try context.fetch(FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.day == day })).first { record.seconds += slice.seconds }
                else { context.insert(ReadingDay(day: day, seconds: slice.seconds)) }
            }
            try context.save()
        } catch { /* A statistics failure must not interrupt reading. */ }
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
}
