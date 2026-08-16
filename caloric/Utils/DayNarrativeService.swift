//
//  DayNarrativeService.swift
//  caloric
//
//  Turns a DayDeltaSummary into a few paragraphs of plain language.
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
//  models drift on, so a capable model buys reliability back for a small
//  part of the savings — and it stays on open weights, because this runs on
//  every user who taps the button and per-token price is the lever that
//  matters at that volume.

import Foundation

struct DayNarrativeService {

    /// The text behind the dashboard's "Dein Tag im Vergleich" button.
    ///
    /// Nothing generates it in the background: it costs a few hundred tokens
    /// and most days nobody opens it. It is requested when the button is
    /// pressed and never before.
    struct DeepDive: Codable, Equatable {
        /// One to four paragraphs — as many as the day actually warrants.
        /// Inline `**…**` marks the figures.
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

    /// Open weights, in preference order. OpenRouter takes the first entry as
    /// the model and falls through the rest when one is unavailable, retired
    /// or refusing the request — so a slug going away degrades the text
    /// instead of emptying the sheet.
    ///
    /// Gemini Flash leads: this prompt is almost entirely instruction rather
    /// than reasoning — no field names in the prose, a length that follows the
    /// data, never a number that is not in the JSON — and Flash holds a brief
    /// like that more reliably than the open-weight models behind it, at a
    /// per-token price in the same range.
    ///
    /// The generation before it sits second so a slug that is retired or not
    /// yet live degrades instead of failing, and Kimi K2 stays as the
    /// open-weight floor in case Google is unreachable altogether.
    ///
    /// Three entries, not four: OpenRouter rejects a longer list outright
    /// ("'models' array must have 3 items or fewer").
    private static let models = [
        "google/gemini-3.7-flash",
        "google/gemini-2.5-flash",
        "moonshotai/kimi-k2-0905"
    ]

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// The deep dive's voice.
    ///
    /// Written to read like a person who looked at the numbers and has
    /// something to say about them — a verdict first, then the reason, then
    /// the one thing worth taking away. Someone tapped to get here, so it is
    /// allowed the space a glanceable card would not be.
    private static func deepDivePrompt(language: String, name: String) -> String {
        // A single letter is a placeholder, not a name, and "j, dein Tag …"
        // reads worse than no greeting at all.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let address = firstName.count < 2
            ? "Sprich die Person direkt an, ohne Namen."
            : "Sprich die Person mit ihrem Vornamen an: \(firstName.prefix(1).uppercased())"
              + "\(firstName.dropFirst()). Der Name steht im ersten Satz, danach nicht mehr."
        let localeRule = language == "de"
            ? "Schreibe auf Deutsch und duze die Person."
            : "Write in English and address the person directly by name."

        return """
        Du schreibst in der App Caloric den Tagesvergleich. Die Person hat \
        dafür bewusst auf einen Button getippt — sie will wissen, wie ihr Tag \
        gerade läuft und woran das liegt.

        \(address)

        Länge: so lang, wie die Daten es hergeben, und keine Zeile länger. \
        Ein Tag, an dem sich kaum etwas bewegt hat, ist mit einem einzigen \
        Absatz vollständig erklärt. Ein Tag mit Workout, auffälliger \
        Alltagsbewegung und klarem Abstand zum Schnitt darf drei bis vier. \
        Jeder Absatz zwei bis drei Sätze. Absätze, die nur wiederholen, was \
        schon dasteht, lässt du weg — Vollständigkeit ist kein Ziel.

        Wenn Absätze da sind, dann in dieser Reihenfolge:
        1. Wo der Tag gerade steht, im ersten Satz, mit der Zahl dahinter.
        2. Woran das liegt: der Teil des Tages, der den Unterschied macht \
        (leadWith), belegt mit Zahlen — und wo möglich mit dem, was dahinter \
        steckt (Schritte, Workout-Minuten, Stehminuten) statt nur mit kcal.
        3. Die Einordnung gegenüber gestern oder dem Schnitt, oder was \
        dagegen läuft. Gibt es einen Haken, nennst du ihn hier offen.
        4. Eine Beobachtung aus highlights, die überrascht — nur wenn sie \
        wirklich überrascht.

        Ton: warm, direkt, respektvoll. Wie jemand, der die Zahlen gelesen \
        hat und sich ehrlich freut, wenn etwas gut lief, und es genauso ruhig \
        sagt, wenn nicht. Kein Coach-Geschrei, keine Ausrufezeichen-Ketten, \
        keine Floskeln, keine Überschriften, keine Aufzählungszeichen.

        Sprache: durchgehend normales Deutsch. Die Bezeichnungen aus den \
        Daten — bmr, neat, eat, tef, caffeine, isPartialDay, leadWith, \
        highlights, weekly und so weiter — tauchen im Text NIE auf, weder \
        einzeln noch in Wörtern wie "eat-Komponente". Du schreibst \
        Grundumsatz, Alltagsbewegung, Workouts, Verdauung, Koffein. Statt \
        "isPartialDay ist true" schreibst du, dass der Tag noch läuft. Wer \
        den Text liest, darf nicht merken, dass dahinter Datenfelder stehen.

        Formatierung: Setze die Zahlen, auf die es ankommt, in **doppelte \
        Sternchen** — höchstens drei pro Absatz, sonst ist der Text \
        gesprenkelt statt betont. Keine Emojis, an keiner Stelle.

        Harte Regeln:
        - Nenne ausschließlich Zahlen, die im JSON stehen. Rechne nichts aus, \
        leite nichts ab, schätze nichts dazu. Eine erfundene Zahl ist der \
        einzige Fehler, den dieser Text nicht machen darf.
        - todayTotal ist der Stand in diesem Moment, nicht der fertige Tag. \
        Wenn isPartialDay true ist, ist das der Zwischenstand nach den \
        bisherigen Stunden, während der Vortag komplett ist. Sag das in \
        eigenen Worten und lies die Differenz nicht als Rückgang. Der \
        Wochenschnitt besteht ebenfalls aus vollen Tagen.
        - Ist eine Komponente heute null oder kaum verändert, lass sie weg. \
        Ein früher Vormittag hat wenig zu erzählen, und das ist in Ordnung.
        - Erwähne den Grundumsatz nur, wenn bmrFactorsChanged true ist. Sonst \
        ist seine Differenz reines Modellrauschen.
        - Wenn foodLoggedToday oder foodLoggedPreviousDay false ist, deute \
        die Verdauung nicht — dann fehlen die Einträge. Sag das lieber.
        - Fehlt weekly, vergleiche nur mit gestern und erfinde keinen Schnitt.
        - Keine medizinischen Ratschläge, keine Diät- oder Trainingspläne, \
        keine moralische Bewertung. Ein leichter, konkreter Anstoß am Ende \
        ist erlaubt, wenn er direkt aus den Zahlen folgt — mehr nicht.
        - Ein schwacher Tag wird nicht schöngeredet, aber auch nicht \
        kleingemacht. Zeig, was trotzdem gut lief.
        \(localeRule)
        """
    }

    /// OpenAI-style strict json_schema: every property required, no extras —
    /// that combination is what "strict" mode demands.
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
    /// why it is the second choice — but a text parsed out of prose beats an
    /// empty sheet.
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
            "model": models[0],
            "models": models,
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
