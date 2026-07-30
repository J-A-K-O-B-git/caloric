import Foundation

enum Secrets {
    static var gcpApiKey: String { required("GCP_API_KEY") }
    static var openRouterApiKey: String { required("OPENROUTER_API_KEY") }

    /// A missing Secrets.xcconfig does not remove the Info.plist entry — the
    /// `$(KEY)` placeholder simply expands to an empty string. Checking only
    /// for nil therefore never fired and the failure surfaced later as an
    /// opaque HTTP error from whichever request used the key.
    private static func required(_ infoKey: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String ?? ""
        guard !value.isEmpty else {
            fatalError("\(infoKey) fehlt oder ist leer – Secrets.xcconfig prüfen")
        }
        return value
    }
}
