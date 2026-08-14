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
//  Routed through OpenRouter rather than a direct provider call. This task is
//  small (a few hundred tokens, text only, no vision) and runs often enough
//  across all users that model cost is the dominant lever — OpenRouter's
//  OpenAI-compatible endpoint gives access to open-weight models at a
//  fraction of a hosted flagship model's price without locking the app to one
//  provider. FoodAnalysisService stays on Gemini: it needs vision for photo
//  input, where open-weight options are weaker and rarely cheaper.
//
//  Model choice is deliberately not the cheapest available. The "invent
//  nothing not in the JSON" rule is exactly the kind of instruction small
//  models drift on, so a mid-size model buys reliability back for a small
//  part of the savings.

import Foundation

struct DayNarrativeService {

    struct Narrative: Codable, Equatable {
        let headline: String
        let body: String
        /// One short, genuinely interesting observation about the day.
        let insight: String
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

    private static let model = "meta-llama/llama-3.3-70b-instruct"

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private static func systemPrompt(language: String) -> String {
        let localeRule = language == "de"
            ? "Schreibe auf Deutsch und duze die Person."
            : "Write in English and address the person directly."

        return """
        Du schreibst die Tagesnotiz in der App Caloric. Sie ist das Erste, was \
        jemand nach dem Öffnen liest. Sie soll sich lohnen: erzähl der Person \
        kurz, wie ihr Tag energetisch gelaufen ist, ordne ihn ein und gib ihr \
        etwas mit, das sie vorher nicht wusste.

        Ton: warm, zugewandt, auf Augenhöhe. Wie jemand, der die Zahlen \
        gelesen hat und sich ehrlich freut, wenn etwas gut lief. Kein \
        Coach-Geschrei, keine Ausrufezeichen-Ketten, keine leeren \
        Motivationsfloskeln. Ein ruhiger, kluger Satz wirkt stärker als drei \
        begeisterte.

        Aufbau der Daten:
        - percentToExplain ist die Kennzahl "% vs. Gestern", die auf dem \
        Bildschirm steht. totalDelta ist die Differenz in kcal dahinter.
        - components zerlegt totalDelta vollständig; shareOfTotalDeltaPercent \
        sagt, wie viel Prozent davon auf eine Komponente entfallen.
        - neatBreakdown zerlegt neat weiter.
        - context liefert die Rohwerte: Schritte, Stehminuten, \
        Workout-Minuten, jeweils auch für den Vortag.
        - weekly vergleicht den Tag mit dem Schnitt der letzten Tage \
        (daysCounted sagt, wie viele es sind).
        - highlights enthält fertig gerechnete Kennzahlen: Aktivanteil, \
        Nachbrennen, kcal je 1.000 Schritte, Wachstunden.

        Was du schreibst — kurz. Das Ganze wird im Vorbeigehen gelesen, \
        nicht studiert:
        - headline: höchstens 50 Zeichen. Die Richtung des Tages, sonst nichts.
        - body: EIN Satz, höchstens 130 Zeichen. Nur der eine Unterschied, \
        der den Tag erklärt — die Komponente unter leadWith, belegt mit genau \
        einer Zahl. Keine zweite Komponente, kein Gegengewicht, keine \
        Einordnung hinterher. Was nicht in einen Satz passt, lässt du weg.
        - insight: EIN Fun Fact, höchstens 90 Zeichen. Überraschend, \
        konkret, aus highlights oder weekly — etwas, das man jemandem \
        erzählen würde. Keine Wiederholung aus dem body, keine Einleitung \
        wie "Übrigens" oder "Interessant ist".

        Kürzer ist immer besser. Drei knappe Zeilen schlagen einen \
        vollständigen Bericht.

        Harte Regeln:
        - Nenne ausschließlich Zahlen, die im JSON stehen. Rechne nichts aus, \
        leite nichts ab, schätze nichts dazu und runde nichts um. Eine \
        erfundene Zahl ist der einzige Fehler, den diese Notiz nicht machen darf.
        - Erwähne den Grundumsatz (bmr) nur, wenn bmrFactorsChanged true ist. \
        Sonst ist seine Differenz reines Modellrauschen.
        - Wenn isPartialDay true ist, zählen für heute nur die bisherigen \
        Stunden, für den Vortag der ganze Tag. Beschreibe den Stand dann als \
        Zwischenstand und deute die Differenz nicht als Rückgang.
        - Wenn foodLoggedToday oder foodLoggedPreviousDay false ist, deute die \
        tef-Differenz nicht — dann fehlen die Einträge. Sag das lieber.
        - Fehlt weekly, vergleiche nur mit gestern und erfinde keinen Schnitt.
        - Keine Gesundheits-, Ernährungs- oder Trainingsempfehlungen, keine \
        moralische Bewertung des Tages. Beschreiben und einordnen, nicht raten.
        - Ein schwacher Tag wird nicht schöngeredet. Sachlich bleiben und, wo \
        es die Daten hergeben, zeigen, was trotzdem gut lief.
        - Komponentennamen: bmr = Grundumsatz, neat = Alltagsbewegung, \
        eat = Workouts, tef = Verdauung, caffeine = Koffein.
        \(localeRule)
        """
    }

    /// OpenAI-style strict json_schema: every property required, no extras —
    /// that combination is what "strict" mode demands.
    private static let responseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "day_narrative",
            "strict": true,
            "schema": [
                "type": "object",
                "properties": [
                    "headline": ["type": "string"],
                    "body":     ["type": "string"],
                    "insight":  ["type": "string"]
                ],
                "required": ["headline", "body", "insight"],
                "additionalProperties": false
            ]
        ]
    ]

    // MARK: - Public API

    /// An open-weight model on OpenRouter is served by a dozen different
    /// providers, and not all of them implement `response_format`. The first
    /// attempt pins routing to those that do; if none is reachable the request
    /// comes back 400/404 and the schema is dropped, the model asked for raw
    /// JSON in prose instead. Losing the schema costs reliability, which is
    /// why it is the second choice — but an explanation parsed out of text
    /// beats an empty card.
    static func explain(_ summary: DayDeltaSummary, language: String) async throws -> Narrative {
        do {
            return try await send(summary, language: language, useSchema: true)
        } catch NarrativeError.requestFailed(let status, _)
                    where [400, 404, 422].contains(status) {
            return try await send(summary, language: language, useSchema: false)
        }
    }

    private static func send(
        _ summary: DayDeltaSummary,
        language: String,
        useSchema: Bool
    ) async throws -> Narrative {
        var prompt = systemPrompt(language: language)
        if !useSchema {
            prompt += """
            \n\nAntworte ausschließlich mit einem JSON-Objekt der Form \
            {"headline": "…", "body": "…", "insight": "…"} — ohne Markdown, \
            ohne Codeblock und ohne Text davor oder dahinter.
            """
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": summary.promptJSON()]
            ],
            // Low temperature: this is a reporting task, not a creative one.
            "temperature": 0.3,
            // Roughly three times what the prompt asks for. Not a length
            // control — the prompt does that — but a ceiling so a model that
            // ignores it cannot bill for an essay.
            "max_tokens": 220
        ]
        if useSchema {
            payload["response_format"] = responseFormat
            // Skip providers that would silently ignore response_format and
            // hand back prose the strict path cannot read.
            payload["provider"] = ["require_parameters": true]
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.openRouterApiKey)", forHTTPHeaderField: "Authorization")
        // Attribution headers OpenRouter uses for its public rankings — optional,
        // but free to set and cost nothing.
        request.setValue("https://caloric.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Caloric", forHTTPHeaderField: "X-Title")
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

        let envelope = try JSONDecoder().decode(OpenRouterEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content,
              let jsonData = Self.jsonObject(in: content) else {
            throw NarrativeError.unreadableResult
        }
        return try JSONDecoder().decode(Narrative.self, from: jsonData)
    }

    /// The outermost `{…}` of a reply. Without the schema models like to wrap
    /// the object in a ```json fence or introduce it with a sentence, and both
    /// make a plain decode fail.
    private static func jsonObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    // MARK: - API envelope

    private struct OpenRouterEnvelope: Codable {
        struct Choice: Codable {
            struct Message: Codable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
