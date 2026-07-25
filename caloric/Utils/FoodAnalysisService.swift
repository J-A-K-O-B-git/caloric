//
//  FoodAnalysisService.swift
//  caloric
//
//  Single entry point for the AI-backed meal analysis used by the journal.
//  Accepts either a text description or a photo and returns the recognised
//  items with their macros. The caller decides what ends up in the journal —
//  this service never writes state.
//
//  Endpoint, model and prompt live here so there is exactly one place to
//  change them.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct FoodAnalysisService {

    // MARK: - Input

    enum Input {
        case text(String)
        /// JPEG data, already downscaled — see `UIImage.jpegForAnalysis()`.
        case photo(Data)
    }

    // MARK: - Errors

    enum AnalysisError: LocalizedError {
        case emptyInput
        case requestFailed(status: Int, body: String)
        case unreadableResult

        var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Keine Eingabe zum Analysieren."
            case .requestFailed(let status, let body):
                return "Analyse fehlgeschlagen (HTTP \(status)): \(body)"
            case .unreadableResult:
                return "Die Antwort konnte nicht gelesen werden."
            }
        }
    }

    // MARK: - Configuration

    private static let model = "gemini-3.5-flash"

    private static var endpoint: URL? {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/"
            + "\(model):generateContent?key=\(Secrets.gcpApiKey)")
    }

    private static let systemPrompt = """
    Du bist ein präziser Ernährungsanalyst für die App Caloric. Analysiere die \
    Mahlzeit des Nutzers und zerlege sie in ihre einzelnen Bestandteile. Schätze \
    für jeden Bestandteil das Gewicht in Gramm sowie Protein, Kohlenhydrate und \
    Fett in Gramm. Bei Fotos schätzt du die Portionsgrößen anhand erkennbarer \
    Referenzen wie Teller, Besteck oder Gläser. Berücksichtige auch Zutaten, die \
    typischerweise mitverwendet werden, aber schwer sichtbar sind, etwa Öl, \
    Butter oder Sauce. Benenne jeden Bestandteil kurz und auf Deutsch. Antworte \
    ausschließlich im vorgegebenen JSON-Schema ohne Erklärungen oder Markdown.
    """

    /// Item list instead of a single macro sum — lets the user verify and
    /// correct individual portions before anything is written.
    private static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "items": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name":    ["type": "STRING"],
                        "grams":   ["type": "NUMBER"],
                        "protein": ["type": "NUMBER"],
                        "carbs":   ["type": "NUMBER"],
                        "fat":     ["type": "NUMBER"]
                    ],
                    "required": ["name", "grams", "protein", "carbs", "fat"]
                ]
            ]
        ],
        "required": ["items"]
    ]

    // MARK: - Public API

    static func analyze(_ input: Input) async throws -> [FoodItem] {
        guard let url = endpoint else { throw AnalysisError.emptyInput }

        // The image travels inline as base64 in the same multimodal request —
        // no separate upload step is needed at this size.
        let userParts: [[String: Any]]
        switch input {
        case .text(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AnalysisError.emptyInput }
            userParts = [["text": trimmed]]

        case .photo(let jpeg):
            guard !jpeg.isEmpty else { throw AnalysisError.emptyInput }
            userParts = [
                ["text": "Analysiere diese Mahlzeit."],
                ["inlineData": [
                    "mimeType": "image/jpeg",
                    "data": jpeg.base64EncodedString()
                ]]
            ]
        }

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": userParts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        // Photo requests take noticeably longer than text ones.
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError.unreadableResult
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "–"
            throw AnalysisError.requestFailed(status: http.statusCode, body: body)
        }

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let json = envelope.candidates.first?.content.parts.first?.text,
              let jsonData = json.data(using: .utf8) else {
            throw AnalysisError.unreadableResult
        }

        let parsed = try JSONDecoder().decode(FoodAnalysisResponse.self, from: jsonData)
        // Drop entries the model returned as pure noise (no mass, no macros).
        return parsed.items.filter { $0.grams > 0 || $0.kcal > 0 }
    }

    // MARK: - API envelope

    private struct GeminiEnvelope: Codable {
        struct Candidate: Codable {
            struct Content: Codable {
                struct Part: Codable { let text: String }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }
}

// MARK: - Image preparation

#if canImport(UIKit)
extension UIImage {
    /// Downscales to `maxEdge` and encodes as JPEG.
    ///
    /// A full-resolution iPhone photo is several megabytes and buys no accuracy
    /// for food recognition — it only costs tokens and latency. It also
    /// converts HEIC to JPEG, which the request format needs anyway.
    func jpegForAnalysis(maxEdge: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let longestEdge = max(size.width, size.height)
        guard longestEdge > 0 else { return nil }

        let factor = longestEdge > maxEdge ? maxEdge / longestEdge : 1
        let target = CGSize(width: (size.width * factor).rounded(),
                            height: (size.height * factor).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
#endif
