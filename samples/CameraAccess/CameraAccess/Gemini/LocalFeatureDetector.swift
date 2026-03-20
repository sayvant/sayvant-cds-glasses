import Foundation

/// Instant on-device feature detection from speech transcript.
/// Runs simple keyword/regex matching to provide provisional clinical signals
/// while waiting for the full backend analysis.
///
/// Pipeline:
///   STT partial (~100ms) -> LocalFeatureDetector.scan() -> provisional features
///   Backend response (~3-5s) -> replaces provisional with authoritative results
///
/// Patterns derived from chest_pain.yaml in the PA backend.
/// Feature IDs match the config so provisional and authoritative results
/// can be merged by ID without translation.
struct LocalFeatureDetector {

    struct DetectedFeature {
        let id: String           // matches chest_pain.yaml feature IDs
        let label: String        // short HUD chip label (max 12 chars)
        let isRedFlag: Bool      // triggers immediate HUD red flag banner
        let isHighPriority: Bool // triggers immediate flush + backend analysis
    }

    // MARK: - Public API

    /// Scan transcript text and return all detected features.
    /// Designed to be called on every STT partial -- must be fast (<5ms).
    static func scan(_ text: String) -> [DetectedFeature] {
        let lower = text.lowercased()
        var found: [DetectedFeature] = []

        for entry in patterns {
            if entry.regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                found.append(entry.feature)
            }
        }

        return found
    }

    /// Check if text contains any instant red-flag triggers.
    static func hasRedFlag(_ text: String) -> DetectedFeature? {
        let lower = text.lowercased()
        for entry in patterns where entry.feature.isRedFlag {
            if entry.regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return entry.feature
            }
        }
        return nil
    }

    /// Check if new text (since last scan) contains high-priority keywords
    /// that should trigger immediate backend analysis.
    static func hasHighPriority(_ text: String) -> Bool {
        let lower = text.lowercased()
        for entry in patterns where entry.feature.isHighPriority {
            if entry.regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Pattern Storage

    private struct PatternEntry {
        let regex: NSRegularExpression
        let feature: DetectedFeature
    }

    private static func compile(_ pattern: String) -> NSRegularExpression {
        // Force-unwrap is intentional: patterns are compile-time constants.
        // A crash here means a dev broke a regex, which should fail loud.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - Patterns
    // Ordered by clinical priority. Red flags first, then ACS symptoms,
    // then risk factors, then protective findings.

    private static let patterns: [PatternEntry] = [

        // =====================================================================
        // RED FLAGS (isRedFlag: true, isHighPriority: true)
        // =====================================================================

        // Cocaine / stimulant use -- coronary vasospasm risk, no beta-blockers
        PatternEntry(
            regex: compile(#"\b(cocaine|coke|crack|meth|amphetamine|stimulant)\w*\b"#),
            feature: DetectedFeature(
                id: "has_cocaine",
                label: "COCAINE",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // Syncope -- hemodynamic compromise
        PatternEntry(
            regex: compile(#"\b(syncope|faint\w*|pass\w*\s*out|black\w*\s*out|collaps\w*)\b"#),
            feature: DetectedFeature(
                id: "has_syncope",
                label: "SYNCOPE",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // Tearing pain -- aortic dissection pattern
        PatternEntry(
            regex: compile(#"\b(tearing|ripping|ripped|tore)\b"#),
            feature: DetectedFeature(
                id: "tearing_quality",
                label: "TEARING",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // Worst pain ever -- maximal severity
        PatternEntry(
            regex: compile(#"\b(worst|10\s*(out\s*of|\/\s*)10|excruciating|unbearable)\b"#),
            feature: DetectedFeature(
                id: "severe_pain",
                label: "WORST PAIN",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // Sudden onset
        PatternEntry(
            regex: compile(#"\b(sudden\w*|abrupt\w*|out\s*of\s*nowhere)\b"#),
            feature: DetectedFeature(
                id: "sudden_onset",
                label: "SUDDEN",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // Severe dyspnea / can't breathe
        PatternEntry(
            regex: compile(#"\b(can.?t\s*(breathe?|catch)|severe\w*\s*(short\w*\s*of\s*breath|dyspnea|sob))\b"#),
            feature: DetectedFeature(
                id: "severe_dyspnea",
                label: "CAN'T BRTH",
                isRedFlag: true,
                isHighPriority: true
            )
        ),

        // =====================================================================
        // ACS SYMPTOMS (isRedFlag: false, isHighPriority: true)
        // =====================================================================

        // Substernal / pressure / heaviness / squeezing
        PatternEntry(
            regex: compile(#"\b(substernal|pressure|squeez\w*|heavy|heaviness|crush\w*|elephant|tight\w*|vise)\b"#),
            feature: DetectedFeature(
                id: "has_pressure",
                label: "PRESSURE",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Radiation to arm / jaw / neck / shoulder
        PatternEntry(
            regex: compile(#"\b(radiat\w*|left\s*arm|goes?\s+to.{0,10}(arm|jaw|neck|shoulder)|(arm|jaw|neck|shoulder).{0,10}(pain|hurt|numb|tingl))\b"#),
            feature: DetectedFeature(
                id: "has_radiation",
                label: "RAD ARM",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Diaphoresis / sweating / drenched / soaked
        PatternEntry(
            regex: compile(#"\b(sweat\w*|diaphore\w*|clammy|perspir\w*|drench\w*|soak\w*)\b"#),
            feature: DetectedFeature(
                id: "has_diaphoresis",
                label: "DIAPHORESIS",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Nausea / vomiting
        PatternEntry(
            regex: compile(#"\b(nausea|vomit\w*|sick|queasy|throw\w*\s*up)\b"#),
            feature: DetectedFeature(
                id: "has_nausea",
                label: "NAUSEA",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Exertional trigger
        PatternEntry(
            regex: compile(#"\b(exertion\w*|shovel\w*|climb\w*|running|stair\w*|mow\w*|yard\s*work|physical\s*activity)\b"#),
            feature: DetectedFeature(
                id: "has_exertional",
                label: "EXERTIONAL",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Dyspnea (general)
        PatternEntry(
            regex: compile(#"\b(short\w*\s*(of\s*)?breath|dyspnea|breathless|winded|sob|difficulty\s*breath)\b"#),
            feature: DetectedFeature(
                id: "has_dyspnea",
                label: "DYSPNEA",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Prolonged duration
        PatternEntry(
            regex: compile(#"\b(constant|continuous|all\s*day|for\s*(several|few|\d+)\s*hours?)\b"#),
            feature: DetectedFeature(
                id: "has_prolonged",
                label: "PROLONGED",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Rest pain
        PatternEntry(
            regex: compile(#"\b(at\s*rest|sitting\s*(still|down)|lying\s*(down|in\s*bed)|resting)\b"#),
            feature: DetectedFeature(
                id: "has_rest_pain",
                label: "REST PAIN",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Palpitations
        PatternEntry(
            regex: compile(#"\b(palpitat\w*|heart\s*rac\w*|pound\w*|flutter\w*)\b"#),
            feature: DetectedFeature(
                id: "has_palpitations",
                label: "PALPITATIONS",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // =====================================================================
        // RISK FACTORS (isRedFlag: false, isHighPriority: false)
        // =====================================================================

        // Prior CAD / stent / bypass -- strongest risk factor
        PatternEntry(
            regex: compile(#"\b(stent|cabg|bypass|prior\s*(mi|heart\s*attack)|angioplast\w*|heart\s*attack|cath)\b"#),
            feature: DetectedFeature(
                id: "has_prior_cad",
                label: "PRIOR CAD",
                isRedFlag: false,
                isHighPriority: true
            )
        ),

        // Family history of heart disease
        PatternEntry(
            regex: compile(#"\b(family|father|mother|dad|brother|sister).{0,20}(heart|cad|mi|attack)\b"#),
            feature: DetectedFeature(
                id: "has_family_hx",
                label: "FAM HX CAD",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Hypertension
        PatternEntry(
            regex: compile(#"\b(hypertens\w*|high\s*blood\s*pressure|htn)\b"#),
            feature: DetectedFeature(
                id: "has_hypertension",
                label: "HTN",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Hyperlipidemia
        PatternEntry(
            regex: compile(#"\b(hyperlipid\w*|high\s*cholesterol|cholesterol|hld|statin)\b"#),
            feature: DetectedFeature(
                id: "has_hyperlipidemia",
                label: "HLD",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Diabetes
        PatternEntry(
            regex: compile(#"\b(diabet\w*|dm|insulin|metformin|a1c|sugar)\b"#),
            feature: DetectedFeature(
                id: "has_diabetes",
                label: "DIABETES",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Smoking
        PatternEntry(
            regex: compile(#"\b(smok\w*|tobacco|cigarette\w*|pack\s*(a\s*)?day|nicotine)\b"#),
            feature: DetectedFeature(
                id: "has_smoking",
                label: "SMOKER",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Prior DVT/PE
        PatternEntry(
            regex: compile(#"\b(dvt|pulmonary\s*embol\w*|blood\s*clot|anticoagul\w*|blood\s*thin)\b"#),
            feature: DetectedFeature(
                id: "has_prior_dvt_pe",
                label: "DVT/PE HX",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // =====================================================================
        // PROTECTIVE / NEGATIVE INDICATORS (isRedFlag: false, isHighPriority: false)
        // =====================================================================

        // Sharp / stabbing quality -- less likely ACS
        PatternEntry(
            regex: compile(#"\b(sharp|stabb\w*|knife|point\w*\s*pain)\b"#),
            feature: DetectedFeature(
                id: "has_sharp",
                label: "SHARP",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Reproducible on palpation -- less likely ACS
        PatternEntry(
            regex: compile(#"\b(reproduc\w*|palpat\w*|tender\w*|chest\s*wall\s*(pain|tender))\b"#),
            feature: DetectedFeature(
                id: "has_reproducible",
                label: "REPRODUCIBLE",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Pleuritic -- less likely ACS
        PatternEntry(
            regex: compile(#"\b(pleuritic|worse\s*.{0,10}breath|inspir\w*)\b"#),
            feature: DetectedFeature(
                id: "has_pleuritic",
                label: "PLEURITIC",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Burning / heartburn -- GERD pattern
        PatternEntry(
            regex: compile(#"\b(burning|burn|heartburn|indigestion)\b"#),
            feature: DetectedFeature(
                id: "has_burning",
                label: "BURNING",
                isRedFlag: false,
                isHighPriority: false
            )
        ),

        // Positional variation -- pericarditis / MSK pattern
        PatternEntry(
            regex: compile(#"\b(lean\w*\s*forward|worse\s*(lying|flat)|better\s*(sitting|leaning))\b"#),
            feature: DetectedFeature(
                id: "has_positional",
                label: "POSITIONAL",
                isRedFlag: false,
                isHighPriority: false
            )
        ),
    ]
}
