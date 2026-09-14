import Foundation
import CoreMotion

@MainActor
public final class PedometerService: ObservableObject {
    @Published public var todaySteps: Int = 4280
    @Published public var distanceMeters: Double = 3120.0
    @Published public var currentPaceSecPerMeter: Double?
    @Published public var isAvailable: Bool = false

    private let pedometer = CMPedometer()

    public init() {}

    public func start() {
        guard CMPedometer.isStepCountingAvailable() else {
            isAvailable = false
            return
        }
        isAvailable = true

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            Task { @MainActor in
                self.todaySteps = d.numberOfSteps.intValue
                if let dist = d.distance {
                    self.distanceMeters = dist.doubleValue
                }
                if let pace = d.currentPace {
                    self.currentPaceSecPerMeter = pace.doubleValue
                }
            }
        }
    }

    public func stop() {
        pedometer.stopUpdates()
    }
}
