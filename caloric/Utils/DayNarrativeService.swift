//
//  DayNarrativeService.swift
//  caloric
//
//  Turns a DayDeltaSummary into one or two sentences of plain language.
//
//  The division of labour is deliberate: DayDeltaSummary computes, this
//  service only formulates. The model receives finished, rounded numbers and
//  is told it may not derive new ones — inventing a figure the app never
//  computed is the main failure mode of a feature like this.
//

import Foundation

struct DayNarrativeService {

    struct Narrative: Codable, Equatable {
        let headline: String
        let body: String
    }

    enum NarrativeError: LocalizedError {
        case requestFailed(status: Int, body: String)
        case unreadableResult

        var errorDescription: String? {
            switch self {
            case .requestFailed(let status, let body):
                return "Erklärung fehlgeschlagen (HTTP \(status)): \(body)"
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

    private static func systemPrompt(language: String) -> String {
        let localeRule = language == "de"
            ? "Antworte auf Deutsch und duze die Person."
            : "Answer in English and address the person directly."

        return """
        In der App Caloric steht dem Nutzer eine Kennzahl vor Augen: \
        "% vs. Gestern". Deine einzige Aufgabe ist, genau diese Zahl zu \
        erklären — woran es liegt, dass sie so ausfällt. Du bekommst sie als \
        percentToExplain zusammen mit ihrer Zerlegung als JSON.

        Aufbau der Daten:
        - percentToExplain ist die Zahl, die erklärt werden soll.
        - totalDelta ist die Differenz in kcal dahinter.
        - components zerlegt totalDelta vollständig. Die delta-Werte der \
        Komponenten ergeben zusammen totalDelta, und \
        shareOfTotalDeltaPercent sagt, wie viel Prozent der Gesamtdifferenz \
        auf eine Komponente entfallen.
        - neatBreakdown zerlegt die Komponente neat weiter.
        - context liefert die Rohwerte dahinter (Schritte, Stehminuten, \
        Workout-Minuten), mit denen du den Grund benennen kannst.

        Regeln:
        - Nenne ausschließlich Zahlen, die im JSON stehen. Rechne nichts aus, \
        leite nichts ab und schätze nichts dazu.
        - Beginne mit der Komponente, die unter leadWith steht. Sie ist bereits \
        als Hauptursache bestimmt — wähle keine andere.
        - Nenne höchstens zwei Komponenten. Wenn eine zweite gegenläufig ist \
        und einen spürbaren Anteil hat, erwähne sie als Gegengewicht.
        - Belege die Ursache mit einem Rohwert aus context, wo es passt, etwa \
        der Schrittzahl gegenüber dem Vortag.
        - Wenn isPartialDay true ist, zählen für heute nur die bisherigen \
        Stunden, für den Vortag der ganze Tag. Bleib dann bei der Beschreibung \
        der aktuellen Werte im Vergleich zum Vortag und deute die Differenz \
        nicht als Rückgang.
        - Erwähne den Grundumsatz (bmr) nur, wenn bmrFactorsChanged true ist. \
        Andernfalls ist seine Differenz reines Modellrauschen und keine \
        Aussage über den Tag.
        - Wenn foodLoggedToday oder foodLoggedPreviousDay false ist, deute die \
        tef-Differenz für diesen Tag nicht — dann fehlen schlicht die \
        Einträge. Sag das lieber, statt es zu interpretieren.
        - Bleib beschreibend. Gib keine Gesundheits-, Ernährungs- oder \
        Trainingsempfehlungen und bewerte den Tag nicht moralisch.
        - Komponentennamen: bmr = Grundumsatz, neat = Alltagsbewegung, \
        eat = Workouts, tef = Verdauung, caffeine = Koffein.
        - headline: eine kurze Zeile, höchstens 60 Zeichen, die die Richtung \
        auf den Punkt bringt.
        - body: zwei bis drei Sätze, sachlich und ohne Aufzählungszeichen.
        \(localeRule)
        """
    }

    private static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "headline": ["type": "STRING"],
            "body":     ["type": "STRING"]
        ],
        "required": ["headline", "body"]
    ]

    // MARK: - Public API

    static func explain(_ summary: DayDeltaSummary, language: String) async throws -> Narrative {
        guard let url = endpoint else { throw NarrativeError.unreadableResult }

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt(language: language)]]],
            "contents": [["parts": [["text": summary.promptJSON()]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema,
                // Low temperature: this is a reporting task, not a creative one.
                "temperature": 0.3
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NarrativeError.unreadableResult
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "–"
            throw NarrativeError.requestFailed(status: http.statusCode, body: body)
        }

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let json = envelope.candidates.first?.content.parts.first?.text,
              let jsonData = json.data(using: .utf8) else {
            throw NarrativeError.unreadableResult
        }
        return try JSONDecoder().decode(Narrative.self, from: jsonData)
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
