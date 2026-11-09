import UIKit
import GameController

/// Where a hardware keyboard's keys go, for a log that can say why they don't reach the Mac: which events
/// the app gets at all, which window and view hold the keyboard, and what GameController sees. Never which keys.
enum KeyTrace {
    private static var installed = false
    private static var seen: [Int: Int] = [:]
    private static var timer: Timer?
    private static var gameController = ""
    private static var gameControllerChanges = 0
    fileprivate static weak var found: UIResponder?

    static func start() {
        if !installed,
           let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
           let traced = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.henge_traceSendEvent(_:))) {
            installed = true
            method_exchangeImplementations(original, traced)
        }
        snapshot("session")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in pollGameController() }
    }

    static func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func snapshot(_ why: String) {
        HengeLog.log("keytrace", "\(why): \(focus())")
    }

    /// Every event the app is given passes here, before any window or view.
    fileprivate static func saw(_ event: UIEvent) {
        let type = event.type.rawValue
        let n = (seen[type] ?? 0) + 1
        seen[type] = n
        guard event.type == .presses else {
            if n == 1 { HengeLog.log("keytrace", "first event of type \(type)") }
            return
        }
        guard n <= 12 || n % 100 == 0 else { return }
        let presses = (event as? UIPressesEvent)?.allPresses ?? []
        let kinds = presses.map { press -> String in
            guard let key = press.key else { return "press type \(press.type.rawValue)" }
            return (0xe0...0xe7).contains(key.keyCode.rawValue) ? "modifier" : "key"
        }
        let phases = presses.map { "\($0.phase.rawValue)" }
        HengeLog.log("keytrace", "presses event \(n): \(kinds.joined(separator: ",")) phases \(phases.joined(separator: ",")); \(focus())")
    }

    private static func focus() -> String {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let key = windows.first { $0.isKeyWindow }
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.henge_traceFound), to: nil, from: nil, for: nil)
        let state: String
        switch key?.windowScene?.activationState {
        case .foregroundActive?: state = "active"
        case .foregroundInactive?: state = "inactive"
        case .background?: state = "background"
        case .unattached?: state = "unattached"
        default: state = "none"
        }
        let keyName = key.map { String(describing: type(of: $0)) } ?? "none"
        let responder = found.map { String(describing: type(of: $0)) } ?? "none"
        return "key window \(keyName) (of \(windows.count)), scene \(state), first responder \(responder)"
    }

    /// Whether GameController knows of a keyboard, and of a key held on it, even when it calls no handler.
    private static func pollGameController() {
        let keyboard = GCKeyboard.coalesced
        let now = keyboard == nil ? "none" : keyboard?.keyboardInput?.isAnyKeyPressed == true ? "a key down" : "no key down"
        guard now != gameController, gameControllerChanges < 30 else { return }
        gameController = now
        gameControllerChanges += 1
        HengeLog.log("keytrace", "GameController keyboard: \(now)")
    }
}

extension UIApplication {
    /// Swapped with sendEvent(_:), so calling itself calls UIKit's.
    @objc func henge_traceSendEvent(_ event: UIEvent) {
        KeyTrace.saw(event)
        henge_traceSendEvent(event)
    }
}

extension UIResponder {
    @objc fileprivate func henge_traceFound() {
        KeyTrace.found = self
    }
}
