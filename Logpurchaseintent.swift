import AppIntents
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// KellyLifeIntents (App Intents Extension): "Log Purchase in Kelly Life".
//
// Runs on its own in the background when the Shortcuts "Transaction" automation
// fires, so Kelly Life doesn't have to open (that's what failed before).
// It drops the purchase into the shared App Group; Kelly Life adds it to Finance
// the next time it opens or comes back to the screen.
// KellyLifeIntents target only. The target needs the App Group
// group.com.kelly.kellylife (Signing & Capabilities).
// ─────────────────────────────────────────────────────────────────────────────

struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase in Kelly Life"
    static let description = IntentDescription("Saves a purchase so it appears in Kelly Life's Finance tab.")

    @Parameter(title: "Amount", description: "For example $12.50")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    func perform() async throws -> some IntentResult {
        guard let shared = UserDefaults(suiteName: "group.com.kelly.kellylife") else { return .result() }
        var waiting = shared.array(forKey: "pendingPurchases") as? [[String: Any]] ?? []
        waiting.append([
            "amount": amount,
            "merchant": merchant ?? "",
            "card": card ?? "",
            "date": Date().timeIntervalSince1970,
        ])
        shared.set(waiting, forKey: "pendingPurchases")
        return .result()
    }
}
