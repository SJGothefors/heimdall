import LocalAuthentication
import Observation

@MainActor @Observable
final class DeviceSecurity {
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var message: String?
    private var context: LAContext?
    private var generation = 0

    func unlock() async {
        guard !isAuthenticating else { return }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            isUnlocked = true
            return
        }
        #endif
        isAuthenticating = true
        message = nil
        let requestGeneration = generation
        let context = LAContext()
        self.context = context
        context.localizedCancelTitle = "Keep locked"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { isAuthenticating = false; self.context = nil }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set an iPhone passcode in Settings to protect your local data, then try again."
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "Unlock the maps and media stored on this iPhone.")
            if requestGeneration == generation { isUnlocked = success }
        } catch {
            message = "Heimdall remains locked. Authenticate to continue."
        }
    }

    func lock() {
        generation += 1
        context?.invalidate()
        isUnlocked = false
    }
}
