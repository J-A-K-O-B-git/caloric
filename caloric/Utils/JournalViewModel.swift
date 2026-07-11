import Foundation
import Observation

// 1. Die Netzwerk-Hilfsstrukturen für das Google-API-Format
struct GeminiResponse: Codable {
    let candidates: [Candidate]
}
struct Candidate: Codable {
    let content: Content
}
struct Content: Codable {
    let parts: [Part]
}
struct Part: Codable {
    let text: String
}

@Observable
@MainActor
class JournalViewModel {
    var journalInput: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    // 2. Setze hier deinen funktionierenden API-Key ein
    private let apiKey = Secrets.gcpApiKey
    
    private var apiURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=\(apiKey)")!
    }
    
    func sendFoodTextToAI() async {
        let trimmedInput = journalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": "Du bist ein präziser Ernährungsanalyst für die App Caloric. Analysiere die Mahlzeit des Nutzers. Schätze das Gesamtgewicht der Zutaten, falls keine genauen Grammangaben vorhanden sind. Berechne Protein, Kohlenhydrate und Fett in Gramm für die gesamte Mahlzeit. Antworte ausschließlich im vorgegebenen JSON-Schema ohne Erklärungen oder Markdown."]
                ]
            ],
            "contents": [
                ["parts": [["text": trimmedInput]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "protein": ["type": "NUMBER"],
                        "carbs": ["type": "NUMBER"],
                        "fat": ["type": "NUMBER"]
                    ],
                    "required": ["protein", "carbs", "fat"]
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            // 4. Erste Ebene decodieren (Google API Wrapper)
            let geminiResult = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            // 5. Den inneren JSON-Text extrahieren und in das FoodAnalysisResponse-Objekt decodieren
            if let jsonString = geminiResult.candidates.first?.content.parts.first?.text,
               let jsonData = jsonString.data(using: .utf8) {
                
                let result = try JSONDecoder().decode(FoodAnalysisResponse.self, from: jsonData)
                
                // Daten an dein bestehendes System übergeben
                saveMacrosToBackend(result)
                
                // Eingabefeld leeren
                self.journalInput = ""
            } else {
                throw URLError(.cannotParseResponse)
            }
            
        } catch {
            self.errorMessage = "Fehler bei der Analyse: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func saveMacrosToBackend(_ food: FoodAnalysisResponse) {
        // Hier greifst du auf deine echten berechneten Werte zu
        print("Erfolgreich getrackt - Protein: \(food.protein)g, Carbs: \(food.carbs)g, Fat: \(food.fat)g")
        
        // TODO: Hier befüllst du deine lokalen State-Variablen oder CoreData/SwiftData-Modelle
    }
}
