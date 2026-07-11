import Foundation

enum Secrets {
    static var gcpApiKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GCP_API_KEY") as? String else {
            fatalError("GCP_API_KEY nicht in Info.plist gefunden – Secrets.xcconfig prüfen")
        }
        return key
    }
}
