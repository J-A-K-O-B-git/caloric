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

    /// The long form behind the dashboard's "Dein Tag im Vergleich" button.
    ///
    /// Deliberately not generated with the card above it: this one costs
    /// several times as many tokens and most days nobody opens it. It is
    /// requested when the button is pressed and never before.
    struct DeepDive: Codable, Equatable {
        /// Two to four short paragraphs. Inline `**…**` marks the figures.
        let paragraphs: [String]
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
        - body: höchstens zwei Sätze, zusammen höchstens 200 Zeichen. Der \
        erste nennt den Unterschied, der den Tag erklärt — die Komponente \
        unter leadWith, belegt mit einer Zahl. Der zweite ist optional und \
        nur dann da, wenn er wirklich etwas hinzufügt: eine zweite Komponente, \
        die spürbar gegenläuft, oder wie der Tag gegenüber dem Schnitt steht. \
        Hat er nichts zu sagen, lässt du ihn weg — ein Satz ist eine \
        vollständige Antwort.
        - insight: EIN Fun Fact, höchstens 90 Zeichen. Überraschend, \
        konkret, aus highlights oder weekly — etwas, das man jemandem \
        erzählen würde. Keine Wiederholung aus dem body, keine Einleitung \
        wie "Übrigens" oder "Interessant ist".

        Im Zweifel kürzer. Ein zweiter Satz muss sich verdienen, dass er \
        da steht.

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

    /// The deep dive's voice.
    ///
    /// Written to read like a person who looked at the numbers and has
    /// something to say about them — a verdict first, then the reason, then
    /// the one thing worth taking away. The card above the button is a
    /// glance; this is the version you actually read, so it is allowed the
    /// space the card is not.
    private static func deepDivePrompt(language: String, name: String) -> String {
        let address = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Sprich die Person direkt an, ohne Namen."
            : "Sprich die Person mit ihrem Vornamen an: \(name). Der Name steht "
              + "im ersten Satz, danach nicht mehr."
        let localeRule = language == "de"
            ? "Schreibe auf Deutsch und duze die Person."
            : "Write in English and address the person directly by name."

        return """
        Du schreibst in der App Caloric den ausführlichen Tagesvergleich. Die \
        Person hat dafür bewusst auf einen Button getippt — sie will mehr als \
        die zwei Sätze, die oben schon stehen.

        \(address)

        Aufbau — zwei bis vier Absätze, jeder zwei bis vier Sätze:
        1. Das Urteil über den Tag, sofort im ersten Satz, mit der Zahl, die \
        es trägt. Kein Aufwärmen, kein "Schauen wir mal".
        2. Warum der Tag so ausfiel: die Komponente unter leadWith, belegt mit \
        Zahlen, und wo möglich mit dem Rohwert dahinter (Schritte, \
        Workout-Minuten, Stehminuten) statt nur mit kcal.
        3. Die Einordnung: wie der Tag gegen den Schnitt der letzten Tage \
        steht, oder was gegenläuft. Wenn es einen Haken gibt, nennst du ihn \
        hier offen.
        4. Optional ein letzter Absatz mit dem, was jemand mitnimmt — eine \
        Beobachtung aus highlights, die überrascht.

        Ton: warm, direkt, respektvoll. Wie jemand, der sich ehrlich freut, \
        wenn etwas gut lief, und es genauso ruhig sagt, wenn nicht. Kein \
        Coach-Geschrei, keine Ausrufezeichen-Ketten, keine Floskeln, keine \
        Überschriften und keine Aufzählungszeichen.

        Formatierung: Setze die Zahlen, auf die es ankommt, in **doppelte \
        Sternchen** — aber höchstens drei pro Absatz, sonst ist der Text \
        gesprenkelt statt betont. Ein einzelnes passendes Emoji darf im \
        ersten Absatz stehen, danach keins mehr.

        Harte Regeln:
        - Nenne ausschließlich Zahlen, die im JSON stehen. Rechne nichts aus, \
        leite nichts ab, schätze nichts dazu. Eine erfundene Zahl ist der \
        einzige Fehler, den dieser Text nicht machen darf.
        - Erwähne den Grundumsatz (bmr) nur, wenn bmrFactorsChanged true ist. \
        Sonst ist seine Differenz reines Modellrauschen.
        - Wenn isPartialDay true ist, zählen für heute nur die bisherigen \
        Stunden, für den Vortag der ganze Tag. Beschreibe den Stand dann als \
        Zwischenstand und deute die Differenz nicht als Rückgang.
        - Wenn foodLoggedToday oder foodLoggedPreviousDay false ist, deute die \
        tef-Differenz nicht — dann fehlen die Einträge. Sag das lieber.
        - Fehlt weekly, vergleiche nur mit gestern und erfinde keinen Schnitt.
        - Keine medizinischen Ratschläge, keine Diät- oder Trainingspläne, \
        keine moralische Bewertung. Du darfst am Ende einen leichten, \
        konkreten Anstoß geben, der sich direkt aus den Zahlen ergibt \
        (etwa der Abstand zum Schnitt) — mehr nicht.
        - Ein schwacher Tag wird nicht schöngeredet, aber auch nicht \
        kleingemacht. Zeig, was trotzdem gut lief.
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

    private static let deepDiveResponseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "day_deep_dive",
            "strict": true,
            "schema": [
                "type": "object",
                "properties": [
                    "paragraphs": [
                        "type": "array",
                        "items": ["type": "string"]
                    ]
                ],
                "required": ["paragraphs"],
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
        try await request(
            Narrative.self,
            prompt: systemPrompt(language: language),
            userContent: summary.promptJSON(),
            schema: responseFormat,
            fallbackShape: #"{"headline": "…", "body": "…", "insight": "…"}"#,
            temperature: 0.3,
            maxTokens: 220
        )
    }

    /// The long form, requested only when the user opens it.
    ///
    /// Same data as the card, a different brief: several paragraphs instead of
    /// two sentences, so the ceiling is correspondingly higher.
    static func deepDive(
        _ summary: DayDeltaSummary,
        language: String,
        name: String
    ) async throws -> DeepDive {
        try await request(
            DeepDive.self,
            prompt: deepDivePrompt(language: language, name: name),
            userContent: summary.promptJSON(),
            schema: deepDiveResponseFormat,
            fallbackShape: #"{"paragraphs": ["…", "…", "…"]}"#,
            // A shade warmer than the card. This one is read as a text rather
            // than scanned as a figure, and at 0.3 every day sounds alike.
            temperature: 0.5,
            maxTokens: 700
        )
    }

    private static func request<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        userContent: String,
        schema: [String: Any],
        fallbackShape: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> T {
        do {
            return try await send(type, prompt: prompt, userContent: userContent,
                                  schema: schema, fallbackShape: fallbackShape,
                                  temperature: temperature, maxTokens: maxTokens,
                                  useSchema: true)
        } catch NarrativeError.requestFailed(let status, _)
                    where [400, 404, 422].contains(status) {
            return try await send(type, prompt: prompt, userContent: userContent,
                                  schema: schema, fallbackShape: fallbackShape,
                                  temperature: temperature, maxTokens: maxTokens,
                                  useSchema: false)
        }
    }

    private static func send<T: Decodable>(
        _ type: T.Type,
        prompt basePrompt: String,
        userContent: String,
        schema: [String: Any],
        fallbackShape: String,
        temperature: Double,
        maxTokens: Int,
        useSchema: Bool
    ) async throws -> T {
        var prompt = basePrompt
        if !useSchema {
            prompt += """
            \n\nAntworte ausschließlich mit einem JSON-Objekt der Form \
            \(fallbackShape) — ohne Markdown-Codeblock und ohne Text davor \
            oder dahinter.
            """
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": userContent]
            ],
            // Low temperature: this is a reporting task, not a creative one.
            "temperature": temperature,
            // Roughly three times what the prompt asks for. Not a length
            // control — the prompt does that — but a ceiling so a model that
            // ignores it cannot bill for an essay.
            "max_tokens": maxTokens
        ]
        if useSchema {
            payload["response_format"] = schema
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
        return try JSONDecoder().decode(T.self, from: jsonData)
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
