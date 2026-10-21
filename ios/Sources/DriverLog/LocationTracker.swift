#if os(iOS)
import CoreLocation
import Foundation

/// Streams GPS fixes while a drive is recorded, including with the phone locked.
/// Uses "When In Use" permission plus a background activity session (iOS 17), so the
/// app never needs "Always" access; iOS shows the blue location pill while it records.
@MainActor
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, waiting, recording, denied, unavailable }

    @Published private(set) var state: State = .idle
    var onFix: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var oneShot: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { state = .unavailable; return }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            state = .denied
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if session == nil { session = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
        if state != .recording { state = .waiting }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
        state = .idle
    }

    /// One fresh fix, or nil after `timeout` seconds. Used when a drive ends.
    func currentFix(timeout: TimeInterval = 8) async -> CLLocation? {
        if let l = manager.location, -l.timestamp.timeIntervalSinceNow < 15, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 100 { return l }
        let task = Task { @MainActor () -> CLLocation? in
            await withCheckedContinuation { c in
                oneShot.append(c)
                // While a drive is recording, the next streamed fix answers; otherwise ask once.
                if state == .idle || state == .denied { manager.requestLocation() }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            finishOneShot(nil)
        }
        return await task.value
    }

    private func finishOneShot(_ l: CLLocation?) {
        let waiting = oneShot
        oneShot = []
        for c in waiting { c.resume(returning: l) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for l in locations {
                if self.state == .waiting { self.state = .recording }
                self.onFix?(l)
            }
            if let last = locations.last { self.finishOneShot(last) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied { self.state = .denied }
            self.finishOneShot(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted { self.state = .denied }
            else if self.state == .denied { self.state = .idle }
        }
    }
}
#endif
