import SwiftUI
import Combine
import LocalAuthentication

// ─────────────────────────────────────────────────────────────────────────────
// App Lock — protects Kelly Life with Face ID (or the iPhone passcode as a
// fallback). When on: the app opens locked, re-locks after you leave it
// (immediately or after a few minutes), and hides its content in the app switcher.
//
// Needs "Privacy - Face ID Usage Description" in the CalorieSnap target's Info.
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private let enabledKey = "appLock.enabled"
    private let graceKey = "appLock.graceMinutes"
    private let offeredKey = "appLock.setupOffered"

    @Published private(set) var isEnabled: Bool
    @Published var graceMinutes: Int {
        didSet { UserDefaults.standard.set(graceMinutes, forKey: graceKey) }
    }
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published var message: String?
    /// True the first time the app opens: shows the "Protect with Face ID?" screen.
    @Published var showSetup: Bool

    private var leftAt: Date?

    private init() {
        let on = UserDefaults.standard.bool(forKey: enabledKey)
        isEnabled = on
        isLocked = on
        graceMinutes = UserDefaults.standard.integer(forKey: graceKey)   // 0 = immediately
        showSetup = !on && !UserDefaults.standard.bool(forKey: offeredKey)
    }

    /// Called from the first-launch screen. Returns true if the lock is now on.
    @discardableResult
    func finishSetup(turnOn: Bool) async -> Bool {
        if turnOn { await setEnabled(true) }
        if !turnOn || isEnabled {
            UserDefaults.standard.set(true, forKey: offeredKey)
            showSetup = false
        }
        return isEnabled
    }

    /// "Face ID", "Touch ID" or "Passcode", depending on the iPhone.
    var methodName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var methodIcon: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }

    // MARK: Turning it on and off

    /// Asks for Face ID first, so it can't be switched on if it won't work.
    func setEnabled(_ on: Bool) async {
        guard on != isEnabled else { return }
        let reason = on ? "Turn on Face ID lock for Kelly Life" : "Turn off Face ID lock for Kelly Life"
        guard await authenticate(reason: reason) else { return }
        isEnabled = on
        isLocked = false
        UserDefaults.standard.set(on, forKey: enabledKey)
        message = nil
    }

    // MARK: Locking

    /// Call from ContentView whenever the scene phase changes.
    func sceneChanged(_ phase: ScenePhase) {
        guard isEnabled else { return }
        switch phase {
        case .background:
            leftAt = Date()
            if graceMinutes == 0 { isLocked = true }
        case .active:
            if let left = leftAt, Date().timeIntervalSince(left) >= Double(graceMinutes * 60) {
                isLocked = true
            }
            leftAt = nil
            if isLocked { Task { await unlock() } }
        default:
            break
        }
    }

    func unlock() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "Unlock Kelly Life") {
            isLocked = false
            message = nil
        }
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        // deviceOwnerAuthentication = Face ID, falling back to the iPhone passcode
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set up Face ID or an iPhone passcode in Settings first."
            return false
        }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
            return false
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

// MARK: - Lock screen (also hides the app in the app switcher)

struct AppLockScreen: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(22)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Circle())
                Text("Kelly Life is locked").font(.title3).fontWeight(.semibold)
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Unlock with \(lock.methodName)", systemImage: lock.methodIcon)
                            .font(.headline)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(lock.isAuthenticating)
                }
                if let m = lock.message {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - First-launch screen

struct AppLockSetupView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: lock.methodIcon)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.green)
                .padding(26)
                .background(Color.green.opacity(0.12))
                .clipShape(Circle())
            VStack(spacing: 10) {
                Text("Protect Kelly Life with \(lock.methodName)?")
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("Your weight, health, recipes and finances stay private. Kelly Life will ask for \(lock.methodName) each time you open it.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            if let m = lock.message {
                Text(m).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await lock.finishSetup(turnOn: true) }
                } label: {
                    Label("Turn on \(lock.methodName)", systemImage: lock.methodIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(lock.isAuthenticating)
                Button("Not now") {
                    Task { await lock.finishSetup(turnOn: false) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("You can change this anytime in Profile.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

// MARK: - Setting card for the Profile tab

struct AppLockSettingsCard: View {
    @ObservedObject var lock = AppLock.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: lock.methodIcon)
                    .font(.title3).foregroundColor(.green)
                    .frame(width: 36, height: 36)
                    .background(Color.green.opacity(0.12)).cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock with \(lock.methodName)").font(.subheadline).fontWeight(.semibold)
                    Text("Ask for \(lock.methodName) when opening Kelly Life")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { on in Task { await lock.setEnabled(on) } }
                ))
                .labelsHidden()
                .tint(.green)
            }
            if lock.isEnabled {
                HStack {
                    Text("Lock again after leaving").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Picker("Lock again after", selection: $lock.graceMinutes) {
                        Text("Immediately").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
            if let m = lock.message, !lock.isLocked {
                Text(m).font(.caption).foregroundColor(.red)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}
