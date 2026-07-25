import Foundation

enum Secrets {
    /// A missing Secrets.xcconfig does not remove the Info.plist entry — the
    /// `$(GCP_API_KEY)` placeholder simply expands to an empty string. Checking
    /// only for nil therefore never fired and the failure surfaced later as an
    /// opaque HTTP error from the food analysis.
    static var gcpApiKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "GCP_API_KEY") as? String ?? ""
        guard !key.isEmpty else {
            fatalError("GCP_API_KEY fehlt oder ist leer – Secrets.xcconfig prüfen")
        }
        return key
    }
}
