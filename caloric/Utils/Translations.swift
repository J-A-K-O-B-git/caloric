//
//  Translations.swift
//  caloric
//
//  Alle App-Texte in Deutsch und Englisch
//

import Foundation

struct Translations {
    let language: String

    // --- Allgemeine Buttons ---
    var welcome: String { language == "de" ? "Schön, dass du da bist!" : "It's great to have you here!" }
    var welcomeSubtitle: String { language == "de" ? "Lass uns dein Profil anlegen." : "Let's set up your profile." }
    var getStarted: String { language == "de" ? "Los geht's" : "Get started" }
    var hint: String { language == "de" ? "Hinweis" : "Hint" }
    var next: String { language == "de" ? "Weiter" : "Next" }
    var done: String { language == "de" ? "Fertig" : "Done" }
    var yes: String { language == "de" ? "Ja" : "Yes" }
    var no: String { language == "de" ? "Nein" : "No" }
    var cancel: String { language == "de" ? "Abbrechen" : "Cancel" }

    // --- Fortschrittsleiste: Labels unter den Kreisen ---
    var stepLabels: [String] {
        language == "de"
            ? ["Sex", "Alter", "Gewicht", "Größe", "KFA", "Extra"]
            : ["Sex", "Age", "Weight", "Height", "BF%", "Extra"]
    }

    // --- Seite 1: Geschlecht ---
    var genderQuestion: String { language == "de" ? "Was ist dein Geschlecht?" : "What is your gender?" }
    var genderInfo: String {
        language == "de"
            ? "Dein Geschlecht beeinflusst dein Grundumsatz primär durch das unterschiedliche Hormonprofil."
            : "Your biological sex primarily influences your basal metabolic rate through the different hormone profile."
    }
    var male: String { language == "de" ? "Männlich" : "Male" }
    var female: String { language == "de" ? "Weiblich" : "Female" }

    // --- Seite 2: Alter ---
    var ageQuestion: String { language == "de" ? "Wann wurdest du geboren?" : "When were you born?" }
    var ageInfo: String {
        language == "de"
            ? "Verlangsamte Zellprozesse, eine geringere Organaktivität und hormonelle Umstellungen senken den Energiebedarf im Alter. Der Körper arbeitet insgesamt effizienter, verbraucht dabei jedoch weniger Kalorien."
            : "Slower cellular processes, reduced organ activity, and hormonal changes lower energy requirements in old age. The body functions more efficiently overall, but burns fewer calories in the process."
    }

    // --- Seite 3: Gewicht ---
    var weightQuestion: String { language == "de" ? "Wie viel wiegst du?" : "How much do you weigh?" }
    var weightInfo: String {
        language == "de"
            ? "Die absolute Körpermasse bestimmt den Energiebedarf für grundlegende physiologische Prozesse wie Herzschlag, Atmung, Zellerneuerung und den Energieverbrauch für Bewegung, da mehr Masse mehr Kraft für die Fortbewegung erfordert."
            : "Absolute body mass determines the energy required for basic physiological processes such as heartbeat, breathing, cell renewal, and the energy consumption for movement, as more mass requires more power for locomotion."
    }
    var weightErrorZero: String {
        language == "de"
            ? "Bitte gib ein Gewicht größer als 0 ein."
            : "Please enter a weight greater than 0."
    }
    var weightErrorMax: String {
        language == "de"
            ? "Das Gewicht darf maximal 500 kg (1.102 lb) betragen."
            : "Weight must not exceed 500 kg (1,102 lb)."
    }

    // --- Seite 4: Größe ---
    var heightQuestion: String { language == "de" ? "Wie groß bist du?" : "How tall are you?" }
    var heightInfo: String {
        language == "de"
            ? "Die Körperoberfläche, die proportional zur Größe skaliert, ist ein entscheidender Faktor für den Wärmeaustausch mit der Umgebung und somit eine wichtige Variable für unsere Berechnung."
            : "Body surface area, which scales proportionally with height, is a key factor in heat exchange with the environment and is therefore an important variable in our calculation."
    }
    var heightErrorZero: String {
        language == "de"
            ? "Bitte gib eine Größe größer als 0 ein."
            : "Please enter a height greater than 0."
    }
    var heightErrorMax: String {
        language == "de"
            ? "Die Größe darf maximal 300 cm (9'10\") betragen."
            : "Height must not exceed 300 cm (9'10\")."
    }

    // --- Seite 5: Körperfettanteil ---
    var bodyFatQuestion: String {
        language == "de"
            ? "Kennst du deinen\nKörperfettanteil?"
            : "Do you know your\nbody fat percentage?"
    }
    var bodyFatInfo: String {
        language == "de"
            ? "Das Fettgewebe hat einen deutlich niedrigeren Stoffwechsel als das Muskelgewebe und ist daher ebenfalls ein entscheidender Faktor in unserer Berechnung."
            : "Adipose tissue has a significantly lower metabolic rate than muscle tissue and is therefore also a key factor in our calculation."
    }
    var bodyFatErrorZero: String {
        language == "de"
            ? "Bitte gib einen KFA größer als 0 ein."
            : "Please enter a body fat percentage greater than 0."
    }
    var bodyFatErrorMax: String {
        language == "de"
            ? "Der KFA darf maximal 100% betragen."
            : "Body fat percentage must not exceed 100%."
    }

    // --- Seite 6: Besonderheiten (Stoffwechsel + Schlaf) ---
    var metabolismQuestion: String {
        language == "de"
            ? "Gibt es Besonderheiten in\ndeinem Stoffwechsel?"
            : "Are there any special\nmetabolic conditions?"
    }
    var metabolismInfo: String {
        language == "de"
            ? "Diese Besonderheiten legen fest, wie schnell dein Körper im Ruhezustand Energie verbrennt und wie dein Stoffwechsel eingestellt ist.\n\nDurch ihre Berücksichtigung passt sich die Kalorienberechnung exakt an deinen tatsächlichen Hormonstatus an, statt nur einen Durchschnittswert zu schätzen."
            : "These factors determine how quickly your body burns energy at rest and how your \"metabolism\" is set.\n\n By taking them into account, the calorie calculation is tailored precisely to your actual hormonal status, rather than simply estimating an average value."
    }
    var hypothyroidism: String { language == "de" ? "Schilddrüsenunterfunktion" : "Hypothyroidism" }
    var hyperthyroidism: String { language == "de" ? "Schilddrüsenüberfunktion" : "Hyperthyroidism" }
    var pcos: String { language == "de" ? "PCOS (Polyzystisches Ovarialsyndrom)" : "PCOS (Polycystic Ovary Syndrome)" }
    var menopause: String { language == "de" ? "Menopause / Post-Menopause" : "Menopause / Post-Menopause" }
    var noCondition: String { language == "de" ? "Nein, alles normal" : "No, everything normal" }
    var sleepQuestion: String { language == "de" ? "Wie viele Stunden schläfst du im Durchschnitt pro Nacht?" : "How many hours do you sleep on average per night?" }
    var sleepInfo: String {
        language == "de"
            ? "Die Schlafdauer steuert wichtige Hormone, die dein Hungergefühl kontrollieren und entscheiden, ob dein Körper eher Fett verbrennt oder Muskeln abbaut."
            : "Sleep duration controls important hormones that regulate your appetite and determine whether your body burns fat or breaks down muscle."
    }
    var hours: String { language == "de" ? "Stunden" : "hours" }

    // --- Seite 7: Ergebnis ---
    var resultTitle: String { language == "de" ? "Dein Grundumsatz" : "Your Basal Metabolic Rate" }
    var resultUnit: String { language == "de" ? "kcal / Tag" : "kcal / day" }
    var resultInfo: String {
        language == "de"
            ? "Das ist die Energiemenge, die dein Körper in Ruhe benötigt, um alle lebenswichtigen Funktionen aufrechtzuerhalten. Auch bekannt als Basalmetabolisierungsrate (BMR).\n\n Da du dich tagsüber natürlich auch bewegst, ist es essentiell zusätzlich deine NEAT (Non-Exercise Activity Thermogenesis, also deine Alltagsbewegung) und deine EAT (Exercise Activity Thermogenesis, also deine sportlichen Aktivitäten) täglich zu berücksichtigen."
            : "This is the amount of energy your body needs at rest to maintain all vital functions. Also known as the basal metabolic rate (BMR).\n\n Since you naturally move around during the day, it's essential to also factor in your NEAT (Non-Exercise Activity Thermogenesis, i.e., your daily movement) and your EAT (Exercise Activity Thermogenesis, i.e., your physical activities) on a daily basis."
    }
    var resultContinue: String { language == "de" ? "Zum letzten Schritt" : "To the last step" }

    // --- Seite 8: Danke ---
    var thankYouTitle: String {
        language == "de"
            ? "Vielen Dank für\ndein bisheriges Vertrauen!"
            : "Thank you for\nyour trust so far!"
    }
    var thankYouSubtitle: String {
        language == "de"
            ? "Wir können dir versprechen:\nEs wird sich lohnen."
            : "We can promise you:\nIt will be worth it."
    }

    // --- Seite 9: Apple Health ---
    var healthTitle: String { language == "de" ? "Mit Apple Health\nverbinden?" : "Connect to\nApple Health?" }
    var healthInfo: String {
        language == "de"
            ? "Wie du jetzt weißt, sind deine Bewegungskalorien entscheidend für eine genaue Berechnung. \n\n Um deinen persönlichen Kalorienbedarf also so genau wie möglich zu treffen, benötigt Caloric Zugriff auf deine Aktivitätsdaten."
            : "As you now know, the calories you burn through physical activity are crucial for an accurate calculation. So, in order to estimate your personal calorie needs as accurately as possible, Caloric needs access to your activity data."
    }
    var healthConnect: String { language == "de" ? "Verbinden" : "Connect" }
    var healthSkip: String { language == "de" ? "Später" : "Later" }

    // --- Körperfett-Hilfsseite (Sheet) ---
    var bodyFatHelpTitle: String { language == "de" ? "Körperfettanteil ermitteln" : "Determine body fat percentage" }
    var bodyFatHelpSubtitle: String {
        language == "de"
            ? "Wähle eine Methode, um deinen Körperfettanteil zu schätzen."
            : "Choose a method to estimate your body fat percentage."
    }
    var inBetween: String { language == "de" ? "Ich liege dazwischen" : "I'm in between" }
    var referenceImages: String { language == "de" ? "Beispielbilder" : "Reference images" }
    var calculation: String { language == "de" ? "Berechnung" : "Calculation" }
    var men: String { language == "de" ? "Männer" : "Men" }
    var women: String { language == "de" ? "Frauen" : "Women" }
    var detailedCalculation: String { language == "de" ? "Detaillierte Berechnung" : "Detailed calculation" }
    var calculationPlaceholder: String {
        language == "de"
            ? "Die Infos für die Berechnung folgen noch."
            : "The information for the calculation is coming soon."
    }

    // --- KFA-Berechnung (Umfangs-Formel) ---
    var calcWaistNavel: String { language == "de" ? "Bauchumfang (Bauchnabel)" : "Waist Circumference (Navel)" }
    var calcWaistNarrow: String { language == "de" ? "Taillenumfang (schmalste Stelle)" : "Waist Circumference (Narrowest)" }
    var calcNeck: String { language == "de" ? "Nackenumfang" : "Neck Circumference" }
    var calcUnit: String { "cm" }
    var calcInfo: String {
        language == "de"
            ? "Miss alle Umfänge entspannt stehend in cm. Die Formel kombiniert Bauch-, Taillen- und Nackenumfang mit deiner Körpergröße."
            : "Measure all circumferences while standing relaxed, in cm. The formula combines belly, waist, and neck circumferences with your height."
    }
    var calcResult: String { language == "de" ? "Berechneter KFA" : "Calculated BF%" }
    var calcUseResult: String { language == "de" ? "Diesen Wert verwenden" : "Use this value" }
    var calcInvalidInput: String {
        language == "de"
            ? "Ungültige Eingabe. Bitte überprüfe die Werte."
            : "Invalid input. Please check your values."
    }
    var calcHeightMissing: String {
        language == "de"
            ? "Bitte zuerst deine Körpergröße eingeben (Schritt 4)."
            : "Please enter your height first (step 4)."
    }

    // --- KFA Bilder-Seite ---
    var bfDisclaimer: String {
        language == "de"
            ? "Diese Bilder dienen nur zur groben optischen Orientierung, da sich Fett bei jedem Menschen genetisch anders verteilt. Für exakte Werte wird eine professionelle Messmethode (z. B. Caliper-Zange oder DXA-Scan) empfohlen."
            : "These images are for rough visual orientation only, as fat distribution varies genetically from person to person. For precise values, a professional measurement method (e.g. caliper or DXA scan) is recommended."
    }
    var bfTip: String {
        language == "de"
            ? "Kombiniere die optische Schätzung über die Bilder mit der wissenschaftlichen Berechnungsmethode, um ein möglichst genaues Ergebnis zu erhalten."
            : "Combine the visual estimate from the images with the scientific calculation method to get the most accurate result possible."
    }
    var bfBelowRange: String { language == "de" ? "Unter 10 %" : "Below 10 %" }
    var bfAboveRange: String { language == "de" ? "Über 40 %" : "Above 40 %" }

    // --- Seite 6: Stoffwechsel-Fragebogen ---
    var thyroidSectionTitle: String { language == "de" ? "Schilddrüse" : "Thyroid" }
    var thyroidHypo: String { language == "de" ? "Schilddrüsenunterfunktion (Hypothyreose)" : "Hypothyroidism (Underactive thyroid)" }
    var thyroidHyper: String { language == "de" ? "Schilddrüsenüberfunktion (Hyperthyreose)" : "Hyperthyroidism (Overactive thyroid)" }
    var thyroidNone: String { language == "de" ? "Keine Schilddrüsenerkrankung" : "No thyroid condition" }
    var thyroidTherapyQuestion: String { language == "de" ? "Ist deine Schilddrüse durch Therapie gut eingestellt?" : "Is your thyroid well-controlled through therapy?" }
    var thyroidOptimal: String { language == "de" ? "Ja, gut eingestellt" : "Yes, well-controlled" }
    var thyroidNotOptimal: String { language == "de" ? "Nein / unsicher" : "No / unsure" }
    var thyroidSymptomQuestion: String { language == "de" ? "Welche Symptome hast du aktuell?" : "Which symptoms are you currently experiencing?" }
    var hypoSymptomFatigue: String { language == "de" ? "Anhaltende Müdigkeit / Erschöpfung" : "Persistent fatigue / exhaustion" }
    var hypoSymptomWeightGain: String { language == "de" ? "Gewichtszunahme trotz normaler Ernährung" : "Weight gain despite normal diet" }
    var hypoSymptomCold: String { language == "de" ? "Kälteempfindlichkeit" : "Cold sensitivity" }
    var hypoSymptomSlow: String { language == "de" ? "Verlangsamter Herzschlag oder Denken" : "Slowed heartbeat or thinking" }
    var hypoSymptomHair: String { language == "de" ? "Haarausfall / trockene Haut" : "Hair loss / dry skin" }
    var hyperSymptomHeat: String { language == "de" ? "Hitzegefühl / starkes Schwitzen" : "Heat sensation / heavy sweating" }
    var hyperSymptomWeightLoss: String { language == "de" ? "Gewichtsverlust trotz normalem Essen" : "Weight loss despite normal eating" }
    var hyperSymptomHeart: String { language == "de" ? "Herzrasen / innere Unruhe" : "Heart palpitations / inner restlessness" }
    var hyperSymptomPeriod: String { language == "de" ? "Zyklusstörungen" : "Menstrual irregularities" }
    var pcosSectionTitle: String { "PCOS" }
    var pcosQuestion: String { language == "de" ? "Hast du PCOS?" : "Do you have PCOS?" }
    var pcosInsulinQuestion: String { language == "de" ? "Besteht eine bestätigte Insulinresistenz?" : "Is there a confirmed insulin resistance?" }
    var pcosSymptomQuestion: String { language == "de" ? "Welche dieser Symptome treten bei dir auf?" : "Which of these symptoms do you experience?" }
    var pcosSymptomIrregular: String { language == "de" ? "Unregelmäßige oder ausbleibende Periode" : "Irregular or absent menstrual cycle" }
    var pcosSymptomBlocked: String { language == "de" ? "Blockierter Gewichtsverlust / Stagnation" : "Blocked weight loss / stagnation" }
    var pcosSymptomCarbFatigue: String { language == "de" ? "Müdigkeit nach Kohlenhydraten" : "Fatigue after carbohydrates" }
    var pcosSymptomHair: String { language == "de" ? "Erhöhter Haarwuchs / Akne" : "Increased hair growth / acne" }
    var pcosYes: String { language == "de" ? "Ja, ich habe PCOS" : "Yes, I have PCOS" }
    var pcosNo: String { language == "de" ? "Nein, kein PCOS" : "No, I don't have PCOS" }
    var pcosInsulinYes: String { language == "de" ? "Ja, bestätigt" : "Yes, confirmed" }
    var pcosInsulinNo: String { language == "de" ? "Nein / nicht bekannt" : "No / not known" }
    var calculateBMR: String { language == "de" ? "Grundbedarf kalkulieren" : "Calculate basal rate" }
    
    // --- Aufschlüsselung: Wissenschaftlicher Hintergrund ---
    var breakdownScienceTitle: String { language == "de" ? "Wissenschaftlicher Hintergrund" : "Scientific Background" }
    var breakdownScienceText: String {
        language == "de"
            ? "Dein täglicher Energiebedarf (TDEE) setzt sich aus diesen Faktoren zusammen:\n\n• BMR: Energie für lebenswichtige Funktionen in Ruhe.\n• NEAT: Kalorien durch Alltagsbewegung (Gehen, Stehen).\n• EAT: Energieverbrauch durch gezielten Sport.\n• TEF: Energie zur Verdauung von Nahrung."
            : "Your Total Daily Energy Expenditure (TDEE) consists of these factors:\n\n• BMR: Energy for vital functions at rest.\n• NEAT: Calories from daily movement (walking, standing).\n• EAT: Energy burned through intentional exercise.\n• TEF: Energy needed to digest food."
    }
    
    var bmrDesc: String { language == "de" ? "Energie für lebenswichtige Funktionen in Ruhe." : "Energy for vital functions at rest." }
    var neatDesc: String { language == "de" ? "Kalorien durch Alltagsbewegung (Gehen, Stehen)." : "Calories from daily movement (walking, standing)." }
    var eatDesc: String { language == "de" ? "Energieverbrauch durch gezielten Sport." : "Energy burned through intentional exercise." }
    var tefDesc: String { language == "de" ? "Energie zur Verdauung von Nahrung." : "Energy needed to digest food." }
    var otherDesc: String { language == "de" ? "Sonstige Faktoren (Koffein, Zyklus, etc.)" : "Other factors (Caffeine, cycle, etc.)" }
}
