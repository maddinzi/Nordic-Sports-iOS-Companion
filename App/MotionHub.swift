import CoreMotion
import Foundation

/// The app's one `CMMotionManager` (Apple: one per app), shared by everything that reads raw motion: the phone motion
/// record of a Sensor Record (`PhoneMotionCapture`) and the paired recording (`PairedRecordingSensors`), which can
/// run at the same time. Accelerometer and gyroscope at 100 Hz, raw (not fused). The sensors run while at least one
/// listener is registered.
///
/// A handler gets Core Motion's values unchanged: the sample's timestamp (`CMLogItem.timestamp`, seconds of
/// `CLOCK_UPTIME_RAW`), the accelerometer in g with iOS's sign (-1 g face up), the gyroscope in rad/s. Handlers run
/// on [queue], one at a time.
final class MotionHub {
    static let shared = MotionHub()

    typealias Handler = (_ timestamp: TimeInterval, _ x: Double, _ y: Double, _ z: Double) -> Void

    static let samplingS = 0.01

    /// Serial: samples of both sensors and whatever a listener queues behind them.
    let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "MotionHub"
        return q
    }()

    private let motion = CMMotionManager()
    private let lock = NSLock()
    private var accel: [String: Handler] = [:]
    private var gyro: [String: Handler] = [:]

    var accelerometerAvailable: Bool { motion.isAccelerometerAvailable }
    var gyroscopeAvailable: Bool { motion.isGyroAvailable }

    /// Registers the listener [id] (again: replaces it). A nil handler does not ask for that sensor.
    func add(_ id: String, accel accelHandler: Handler?, gyro gyroHandler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        let accelWasOn = !accel.isEmpty
        let gyroWasOn = !gyro.isEmpty
        accel[id] = accelHandler
        gyro[id] = gyroHandler
        if !accelWasOn, !accel.isEmpty {
            motion.accelerometerUpdateInterval = Self.samplingS
            motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                let a = data.acceleration
                for handler in self.handlers(\.accel) { handler(data.timestamp, a.x, a.y, a.z) }
            }
        }
        if !gyroWasOn, !gyro.isEmpty {
            motion.gyroUpdateInterval = Self.samplingS
            motion.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                let r = data.rotationRate
                for handler in self.handlers(\.gyro) { handler(data.timestamp, r.x, r.y, r.z) }
            }
        }
    }

    /// Removes the listener [id]; a sensor nobody listens to stops.
    func remove(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        let accelWasOn = !accel.isEmpty
        let gyroWasOn = !gyro.isEmpty
        accel[id] = nil
        gyro[id] = nil
        if accelWasOn, accel.isEmpty { motion.stopAccelerometerUpdates() }
        if gyroWasOn, gyro.isEmpty { motion.stopGyroUpdates() }
    }

    private func handlers(_ which: KeyPath<MotionHub, [String: Handler]>) -> [Handler] {
        lock.lock()
        defer { lock.unlock() }
        return Array(self[keyPath: which].values)
    }
}
