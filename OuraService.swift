import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit
import Security

// ─────────────────────────────────────────────────────────────────────────────
// Oura — "Sign in with Oura" (OAuth2 + PKCE) and the v2 API for daily
// readiness and daily sleep scores. Main app target only.
//
// Setup (once): create an app in the Oura developer portal, add the redirect
// URI shown in the app (default kellylife://oura), then paste the Client ID
// and Client Secret into Energy → Connect Oura.
// Secrets and tokens are stored in the iPhone Keychain.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - API models

struct OuraReadinessContributors: Decodable {
    var activityBalance: Int?
    var bodyTemperature: Int?
    var hrvBalance: Int?
    var previousDayActivity: Int?
    var previousNight: Int?
    var recoveryIndex: Int?
    var restingHeartRate: Int?
    var sleepBalance: Int?

    /// Display order + names for the Energy page.
    var list: [(String, Int?)] {
        [("HRV balance", hrvBalance), ("Resting heart rate", restingHeartRate),
         ("Recovery index", recoveryIndex), ("Previous night", previousNight),
         ("Sleep balance", sleepBalance), ("Body temperature", bodyTemperature),
         ("Activity balance", activityBalance), ("Previous day activity", previousDayActivity)]
    }
}

struct OuraReadinessDay: Decodable {
    var day: String
    var score: Int?
    var temperatureDeviation: Double?
    var contributors: OuraReadinessContributors?
}

struct OuraSleepContributors: Decodable {
    var deepSleep: Int?
    var efficiency: Int?
    var latency: Int?
    var remSleep: Int?
    var restfulness: Int?
    var timing: Int?
    var totalSleep: Int?
}

struct OuraSleepDay: Decodable {
    var day: String
    var score: Int?
    var contributors: OuraSleepContributors?
}

/// One ring battery reading. `level` is 0–100.
struct OuraBattery: Decodable {
    var timestamp: String
    var level: Int
    var charging: Bool?
    var inCharger: Bool?

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: timestamp) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: timestamp)
    }
    var isCharging: Bool { charging == true || inCharger == true }
    /// SF Symbol that matches the level.
    var symbol: String {
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct OuraPage<T: Decodable>: Decodable {
    var data: [T]
    var nextToken: String?
}

private struct OuraToken: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Double?
}

enum OuraError: LocalizedError {
    case notConfigured, notConnected, badRedirect(String), server(Int, String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Oura Client ID and Secret first."
        case .notConnected: return "Oura isn't connected."
        case .badRedirect(let why): return "Oura sign-in didn't finish: \(why)"
        case .server(let code, let body): return "Oura error \(code): \(body.prefix(200))"
        }
    }
}

// MARK: - Keychain

enum OuraKeychain {
    private static let service = "com.kelly.kellylife.oura"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String?, for account: String) {
        SecItemDelete(base(account) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Service

@MainActor
final class OuraService: ObservableObject {
    static let shared = OuraService()

    @Published var clientID: String = UserDefaults.standard.string(forKey: "oura.clientID") ?? ""
    @Published var redirectURI: String = UserDefaults.standard.string(forKey: "oura.redirectURI") ?? "kellylife://oura"
    @Published private(set) var isConnected: Bool = OuraKeychain.get("refreshToken") != nil || OuraKeychain.get("accessToken") != nil
    @Published private(set) var isWorking = false
    @Published var lastError: String?
    /// True when the redirect URI is http(s): you approve in Safari, then paste the address back.
    @Published var awaitingPastedRedirect = false

    private let apiBase = "https://api.ouraring.com"
    private let authorizeURL = "https://cloud.ouraring.com/oauth/authorize"
    private let tokenURL = "https://api.ouraring.com/oauth/token"

    private var codeVerifier: String?
    private var authState: String?
    private var authSession: ASWebAuthenticationSession?
    private let anchor = OuraAnchorProvider()
    private var refreshing: Task<Void, Error>?

    var clientSecret: String { OuraKeychain.get("clientSecret") ?? "" }
    var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty && !redirectURI.isEmpty }

    func saveConfig(clientID: String, clientSecret: String, redirectURI: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.clientID, forKey: "oura.clientID")
        UserDefaults.standard.set(self.redirectURI, forKey: "oura.redirectURI")
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty { OuraKeychain.set(secret, for: "clientSecret") }
    }

    // MARK: Sign in

    func connect() {
        lastError = nil
        guard isConfigured else { lastError = OuraError.notConfigured.localizedDescription; return }

        let verifier = Self.randomURLSafe(bytes: 48)                       // 64 chars
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(bytes: 16)
        codeVerifier = verifier
        authState = state

        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            // No "scope" parameter: Oura then grants every scope ticked for this app in the
            // developer portal (daily, heartrate, tag, workout, session, spo2, ring configuration,
            // stress, heart health).
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = c.url, let redirect = URL(string: redirectURI), let scheme = redirect.scheme else {
            lastError = "The redirect URI isn't a valid address."
            return
        }

        if scheme == "http" || scheme == "https" {
            // Can't be caught automatically — approve in Safari, then paste the address back.
            awaitingPastedRedirect = true
            UIApplication.shared.open(url)
            return
        }

        // OuraService is a long-lived singleton, so capturing self strongly here is fine.
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callbackURL, error in
            Task { @MainActor in
                if let callbackURL {
                    await self.handleRedirect(callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    // user closed the sheet
                } else if let error {
                    self.lastError = error.localizedDescription
                }
            }
        }
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    /// For http(s) redirect URIs: paste the full address Safari ended on after approving.
    func finishWithPasted(_ text: String) async {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            lastError = "That doesn't look like an address. Copy the whole address from Safari's address bar."
            return
        }
        await handleRedirect(url)
    }

    func handleRedirect(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let err = value("error") {
            lastError = OuraError.badRedirect(err).localizedDescription; return
        }
        guard let code = value("code") else {
            lastError = OuraError.badRedirect("no code in the address").localizedDescription; return
        }
        if let expected = authState, value("state") != expected {
            lastError = OuraError.badRedirect("security check failed, please try again").localizedDescription; return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            var params = [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "client_secret": clientSecret,
            ]
            if let v = codeVerifier { params["code_verifier"] = v }
            try await requestToken(params)
            awaitingPastedRedirect = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        for key in ["accessToken", "refreshToken"] { OuraKeychain.set(nil, for: key) }
        UserDefaults.standard.removeObject(forKey: "oura.tokenExpiry")
        isConnected = false
    }

    // MARK: Tokens

    private func requestToken(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OuraError.server(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token = try decoder.decode(OuraToken.self, from: data)

        OuraKeychain.set(token.accessToken, for: "accessToken")
        if let r = token.refreshToken { OuraKeychain.set(r, for: "refreshToken") }   // single-use: always keep the newest
        let expiry = Date().addingTimeInterval((token.expiresIn ?? 86_400) - 300)
        UserDefaults.standard.set(expiry, forKey: "oura.tokenExpiry")
        isConnected = true
    }

    private func refreshTokens() async throws {
        if let running = refreshing { return try await running.value }
        let task = Task { @MainActor in
            guard let refresh = OuraKeychain.get("refreshToken") else { throw OuraError.notConnected }
            try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": self.clientID,
                "client_secret": self.clientSecret,
            ])
        }
        refreshing = task
        defer { refreshing = nil }
        try await task.value
    }

    private func validAccessToken() async throws -> String {
        let expiry = UserDefaults.standard.object(forKey: "oura.tokenExpiry") as? Date ?? .distantPast
        if expiry < Date() { try await refreshTokens() }
        guard let token = OuraKeychain.get("accessToken") else { throw OuraError.notConnected }
        return token
    }

    // MARK: Data

    func fetchReadiness(from start: Date, to end: Date) async throws -> [OuraReadinessDay] {
        try await fetchAll("/v2/usercollection/daily_readiness", from: start, to: end)
    }

    func fetchSleep(from start: Date, to end: Date) async throws -> [OuraSleepDay] {
        try await fetchAll("/v2/usercollection/daily_sleep", from: start, to: end)
    }

    /// The ring's most recent battery reading.
    func fetchLatestBattery() async throws -> OuraBattery? {
        guard isConnected else { throw OuraError.notConnected }
        var c = URLComponents(string: apiBase + "/v2/usercollection/ring_battery_level")!
        c.queryItems = [.init(name: "latest", value: "true")]
        let page: OuraPage<OuraBattery> = try await get(c.url!)
        return page.data.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private func fetchAll<T: Decodable>(_ path: String, from start: Date, to end: Date) async throws -> [T] {
        guard isConnected else { throw OuraError.notConnected }
        var results: [T] = []
        var next: String? = nil
        repeat {
            var c = URLComponents(string: apiBase + path)!
            c.queryItems = [.init(name: "start_date", value: Self.dayString(start)),
                            .init(name: "end_date", value: Self.dayString(end))]
            if let next { c.queryItems?.append(.init(name: "next_token", value: next)) }
            let page: OuraPage<T> = try await get(c.url!)
            results += page.data
            next = page.nextToken
        } while next != nil
        return results
    }

    private func get<T: Decodable>(_ url: URL, retried: Bool = false) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && !retried {
            try await refreshTokens()
            return try await get(url, retried: true)
        }
        guard status == 200 else {
            if status == 401 { disconnect() }
            throw OuraError.server(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Helpers

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func date(fromDay s: String) -> Date? {
        dayFormatter.date(from: s).map { Calendar.current.startOfDay(for: $0) }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomURLSafe(bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return base64URL(Data(buffer))
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}

/// Tells the sign-in sheet which window to appear over.
final class OuraAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Setup screen

struct OuraSetupView: View {
    @ObservedObject var oura = OuraService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = OuraService.shared.clientID
    @State private var clientSecret = ""
    @State private var redirectURI = OuraService.shared.redirectURI
    @State private var pasted = ""

    var body: some View {
        NavigationStack {
            Form {
                if oura.isConnected {
                    Section {
                        Label("Oura is connected", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Your Energy page now uses Oura's real Readiness and Sleep scores. It falls back to Apple Health if Oura has no data for a day.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Disconnect Oura", role: .destructive) { oura.disconnect() }
                    }
                }

                Section {
                    Text("1. Open the Oura developer portal and sign in with your Oura account.")
                    Text("2. Create a new application (any name, e.g. \"Kelly Life\").")
                    Text("3. Under Redirect URIs, add exactly:")
                    Text(redirectURI)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text("4. Copy the Client ID and Client Secret into the boxes below.")
                    Link(destination: URL(string: "https://developer.ouraring.com")!) {
                        Label("Open Oura developer portal", systemImage: "safari")
                    }
                } header: {
                    Text("Create your Oura app (one time)")
                } footer: {
                    Text("If the portal doesn't accept kellylife://oura, use http://localhost instead and change it below too. You'll then paste the address back after approving.")
                }

                Section("Your app details") {
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(oura.clientSecret.isEmpty ? "Client Secret" : "Client Secret (saved)", text: $clientSecret)
                    TextField("Redirect URI", text: $redirectURI)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    Button {
                        oura.saveConfig(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI)
                        clientSecret = ""
                        oura.connect()
                    } label: {
                        HStack {
                            Label(oura.isConnected ? "Reconnect Oura" : "Connect Oura", systemImage: "link")
                            if oura.isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(clientID.isEmpty || (clientSecret.isEmpty && oura.clientSecret.isEmpty) || redirectURI.isEmpty)

                    if oura.awaitingPastedRedirect {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("After you tap Allow in Safari, the page won't load. That's expected. Copy the whole address from Safari's address bar and paste it here:")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextField("http://localhost/?code=…", text: $pasted, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.system(.footnote, design: .monospaced))
                            Button("Finish connecting") { Task { await oura.finishWithPasted(pasted) } }
                                .disabled(pasted.isEmpty)
                        }
                    }
                }

                if let err = oura.lastError {
                    Section { Text(err).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect Oura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: oura.isConnected) { _, connected in
                if connected { pasted = "" }
            }
        }
    }
}
