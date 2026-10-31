import Foundation

// Reconnaissance d'accords à partir des notes tenues.
// On travaille sur les classes de hauteur (l'octave ne change pas le nom de
// l'accord), mais on garde la basse réelle pour les renversements.

enum Note {
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flatNames  = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    static let frenchSharp = ["Do", "Do♯", "Ré", "Ré♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    static let frenchFlat  = ["Do", "Ré♭", "Ré", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]

    /// Les tonalités à bémols : on écrit Mi♭ plutôt que Ré♯.
    static let flatRoots: Set<Int> = [1, 3, 5, 8, 10]

    static func name(_ pc: Int, flat: Bool) -> String {
        (flat ? flatNames : sharpNames)[((pc % 12) + 12) % 12]
    }
    static func french(_ pc: Int, flat: Bool) -> String {
        (flat ? frenchFlat : frenchSharp)[((pc % 12) + 12) % 12]
    }
    static func octave(_ midi: Int) -> Int { midi / 12 - 1 }
    static func fullName(_ midi: Int, flat: Bool) -> String {
        "\(name(midi % 12, flat: flat))\(octave(midi))"
    }
}

/// Écriture correcte d'une note selon sa fonction dans l'accord.
/// Un Sol dièse dans un Mi7 n'est pas un La bémol : on nomme la note d'après
/// son degré, pas d'après sa classe de hauteur.
enum Spelling {
    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    static let lettersFR = ["Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"]
    static let naturalPC = [0, 2, 4, 5, 7, 9, 11]

    /// Écriture usuelle de chaque fondamentale : (index de lettre, altération).
    static let rootSpelling: [(Int, Int)] = [
        (0, 0),   // Do
        (1, -1),  // Ré bémol
        (1, 0),   // Ré
        (2, -1),  // Mi bémol
        (2, 0),   // Mi
        (3, 0),   // Fa
        (3, 1),   // Fa dièse
        (4, 0),   // Sol
        (5, -1),  // La bémol
        (5, 0),   // La
        (6, -1),  // Si bémol
        (6, 0),   // Si
    ]

    static func accidental(_ alter: Int) -> String {
        switch alter {
        case -2: return "𝄫"
        case -1: return "♭"
        case 0:  return ""
        case 1:  return "♯"
        case 2:  return "𝄪"
        default: return alter < 0 ? String(repeating: "♭", count: -alter)
                                  : String(repeating: "♯", count: alter)
        }
    }

    static func rootName(_ pc: Int, french: Bool = false) -> String {
        let (l, a) = rootSpelling[((pc % 12) + 12) % 12]
        return (french ? lettersFR : letters)[l] + accidental(a)
    }

    /// Nomme une note d'après la fondamentale et son degré (1, 2, 3, 4, 5, 6, 7).
    static func noteName(rootPC: Int, degree: Int, actualPC: Int, french: Bool) -> String {
        let (rootLetter, _) = rootSpelling[((rootPC % 12) + 12) % 12]
        let letterIndex = (rootLetter + degree - 1) % 7
        let natural = naturalPC[letterIndex]
        var alter = (((actualPC - natural) % 12) + 12) % 12
        if alter > 6 { alter -= 12 }
        guard abs(alter) <= 2 else {
            // Écriture trop tordue : on retombe sur le nom usuel.
            let (l, a) = rootSpelling[((actualPC % 12) + 12) % 12]
            return (french ? lettersFR : letters)[l] + accidental(a)
        }
        return (french ? lettersFR : letters)[letterIndex] + accidental(alter)
    }
}

struct ChordTemplate {
    let intervals: [Int]
    let suffix: String
    let french: String
    /// Départage les ambiguïtés : les accords courants l'emportent.
    let weight: Double
}

enum ChordBook {
    static let templates: [ChordTemplate] = [
        // triades
        .init(intervals: [0, 4, 7],            suffix: "",       french: "majeur",            weight: 3.0),
        .init(intervals: [0, 3, 7],            suffix: "m",      french: "mineur",            weight: 3.0),
        .init(intervals: [0, 3, 6],            suffix: "dim",    french: "diminué",           weight: 1.4),
        .init(intervals: [0, 4, 8],            suffix: "aug",    french: "augmenté",          weight: 1.0),
        .init(intervals: [0, 5, 7],            suffix: "sus4",   french: "suspendu 4",        weight: 1.6),
        .init(intervals: [0, 2, 7],            suffix: "sus2",   french: "suspendu 2",        weight: 1.4),
        // sixtes
        .init(intervals: [0, 4, 7, 9],         suffix: "6",      french: "sixte",             weight: 1.8),
        .init(intervals: [0, 3, 7, 9],         suffix: "m6",     french: "mineur sixte",      weight: 1.6),
        // septièmes
        .init(intervals: [0, 4, 7, 10],        suffix: "7",      french: "septième de dominante", weight: 3.0),
        .init(intervals: [0, 4, 7, 11],        suffix: "maj7",   french: "majeur septième",   weight: 2.8),
        .init(intervals: [0, 3, 7, 10],        suffix: "m7",     french: "mineur septième",   weight: 2.8),
        .init(intervals: [0, 3, 7, 11],        suffix: "m(maj7)", french: "mineur majeur 7",  weight: 1.0),
        .init(intervals: [0, 3, 6, 10],        suffix: "m7♭5",   french: "demi-diminué",      weight: 1.6),
        .init(intervals: [0, 3, 6, 9],         suffix: "dim7",   french: "septième diminuée", weight: 1.4),
        .init(intervals: [0, 5, 7, 10],        suffix: "7sus4",  french: "septième sus4",     weight: 1.6),
        .init(intervals: [0, 4, 8, 10],        suffix: "7♯5",    french: "septième quinte augmentée", weight: 0.9),
        .init(intervals: [0, 4, 6, 10],        suffix: "7♭5",    french: "septième quinte diminuée",  weight: 0.9),
        // ajoutées
        .init(intervals: [0, 2, 4, 7],         suffix: "add9",   french: "ajoutée neuvième",  weight: 1.8),
        .init(intervals: [0, 2, 3, 7],         suffix: "m(add9)", french: "mineur ajoutée 9", weight: 1.4),
        // neuvièmes
        .init(intervals: [0, 2, 4, 7, 10],     suffix: "9",      french: "neuvième",          weight: 2.2),
        .init(intervals: [0, 2, 4, 7, 11],     suffix: "maj9",   french: "majeur neuvième",   weight: 2.2),
        .init(intervals: [0, 2, 3, 7, 10],     suffix: "m9",     french: "mineur neuvième",   weight: 2.2),
        .init(intervals: [0, 1, 4, 7, 10],     suffix: "7♭9",    french: "septième neuvième bémol", weight: 1.2),
        .init(intervals: [0, 3, 4, 7, 10],     suffix: "7♯9",    french: "septième neuvième dièse", weight: 1.2),
        // onzièmes et treizièmes (quinte souvent omise)
        .init(intervals: [0, 2, 4, 5, 7, 10],  suffix: "11",     french: "onzième",           weight: 1.2),
        .init(intervals: [0, 2, 3, 5, 7, 10],  suffix: "m11",    french: "mineur onzième",    weight: 1.4),
        .init(intervals: [0, 2, 4, 7, 9, 10],  suffix: "13",     french: "treizième",         weight: 1.4),
        .init(intervals: [0, 2, 4, 7, 9, 11],  suffix: "maj13",  french: "majeur treizième",  weight: 1.0),
    ]

    static let intervalNames: [Int: (String, String)] = [
        0:  ("1", "unisson"),            1:  ("♭2", "seconde mineure"),
        2:  ("2", "seconde majeure"),    3:  ("♭3", "tierce mineure"),
        4:  ("3", "tierce majeure"),     5:  ("4", "quarte juste"),
        6:  ("♭5", "triton"),            7:  ("5", "quinte juste"),
        8:  ("♭6", "sixte mineure"),     9:  ("6", "sixte majeure"),
        10: ("♭7", "septième mineure"),  11: ("7", "septième majeure"),
    ]
}

struct ChordResult: Equatable {
    var symbol: String          // « Fmaj7/A »
    var quality: String         // « majeur septième »
    var rootPC: Int
    var bassPC: Int
    var notes: [Int]            // notes MIDI réellement tenues, triées
    var noteNames: [String]     // en français
    var degrees: [String]       // « 1 · 3 · 5 · 7 »
    var confidence: Double      // 0…1
    var isInversion: Bool

    static let empty = ChordResult(symbol: "—", quality: "", rootPC: -1, bassPC: -1,
                                   notes: [], noteNames: [], degrees: [],
                                   confidence: 0, isInversion: false)
}

enum ChordDetector {

    static func detect(_ midiNotes: [Int]) -> ChordResult {
        let notes = Array(Set(midiNotes)).sorted()
        guard let bass = notes.first else { return .empty }
        let pcs = Set(notes.map { ($0 % 12 + 12) % 12 })
        let bassPC = (bass % 12 + 12) % 12

        if notes.count == 1 {
            return ChordResult(symbol: Spelling.rootName(bassPC), quality: "note seule",
                               rootPC: bassPC, bassPC: bassPC, notes: notes,
                               noteNames: [Spelling.rootName(bassPC, french: true)],
                               degrees: ["1"], confidence: 1, isInversion: false)
        }

        if pcs.count == 2 {
            let sorted = notes.map { ($0 % 12 + 12) % 12 }
            let interval = ((sorted[sorted.count - 1] - sorted[0]) % 12 + 12) % 12
            let (deg, label) = ChordBook.intervalNames[interval] ?? ("?", "intervalle")
            let sym = interval == 7 ? "\(Spelling.rootName(bassPC))5"
                                    : "\(Spelling.rootName(bassPC)) + \(deg)"
            return ChordResult(symbol: sym, quality: label, rootPC: bassPC, bassPC: bassPC,
                               notes: notes,
                               noteNames: notes.map { Spelling.rootName(($0 % 12 + 12) % 12, french: true) },
                               degrees: ["1", deg], confidence: 0.7, isInversion: false)
        }

        var best: (score: Double, root: Int, tpl: ChordTemplate)? = nil
        for root in 0..<12 {
            let rel = Set(pcs.map { (($0 - root) % 12 + 12) % 12 })
            for tpl in ChordBook.templates {
                let t = Set(tpl.intervals)
                let matched = rel.intersection(t).count
                guard matched >= 3 else { continue }
                let missing = t.subtracting(rel)
                let extra = rel.subtracting(t)
                // La quinte manquante est banale dans un voicing : on ne la punit presque pas.
                let missingCost = missing.reduce(0.0) { $0 + ($1 == 7 ? 0.25 : 2.2) }
                var score = Double(matched) * 2.2 - missingCost - Double(extra.count) * 3.0 + tpl.weight
                if root == bassPC { score += 1.6 }                 // position fondamentale
                if rel.contains(0) { score += 0.8 }                // fondamentale présente
                if best == nil || score > best!.score { best = (score, root, tpl) }
            }
        }

        guard let b = best, b.score > 0 else {
            return ChordResult(symbol: "?", quality: "accord non reconnu", rootPC: -1, bassPC: bassPC,
                               notes: notes,
                               noteNames: notes.map { Spelling.rootName(($0 % 12 + 12) % 12, french: true) },
                               degrees: [], confidence: 0, isInversion: false)
        }

        let rootName = Spelling.rootName(b.root)
        var symbol = rootName + b.tpl.suffix
        let inversion = b.root != bassPC
        if inversion { symbol += "/" + Spelling.rootName(bassPC) }

        let t = Set(b.tpl.intervals)
        let hasSeventh = t.contains(10) || t.contains(11)
        let fifthIsFlat = t.contains(6)      // diminué, demi-diminué
        let fifthIsSharp = t.contains(8) && !t.contains(7)

        /// Degré diatonique (1…7) et étiquette affichée pour chaque intervalle.
        func analyse(_ rel: Int) -> (degree: Int, label: String) {
            switch rel {
            case 0:  return (1, "1")
            case 1:  return (2, hasSeventh ? "♭9" : "♭2")
            case 2:  return (2, hasSeventh || b.tpl.suffix.contains("add9") ? "9" : "2")
            case 3:  return t.contains(4) ? (2, "♯9") : (3, "♭3")
            case 4:  return (3, "3")
            case 5:  return (4, hasSeventh ? "11" : "4")
            case 6:  return fifthIsFlat ? (5, "♭5") : (4, "♯11")
            case 7:  return (5, "5")
            case 8:  return fifthIsSharp ? (5, "♯5") : (6, hasSeventh ? "♭13" : "♭6")
            case 9:  return (6, hasSeventh ? "13" : "6")
            case 10: return (7, "♭7")
            case 11: return (7, "7")
            default: return (1, "?")
            }
        }

        var names: [String] = []
        var degreeLabels: [String] = []
        var seenDegree = Set<String>()
        for n in notes {
            let pc = ((n % 12) + 12) % 12
            let rel = ((pc - b.root) % 12 + 12) % 12
            let a = analyse(rel)
            names.append(Spelling.noteName(rootPC: b.root, degree: a.degree,
                                           actualPC: pc, french: true))
            if seenDegree.insert(a.label).inserted { degreeLabels.append(a.label) }
        }

        let maxScore = Double(b.tpl.intervals.count) * 2.2 + b.tpl.weight + 2.4
        return ChordResult(symbol: symbol,
                           quality: b.tpl.french + (inversion ? " (renversé)" : ""),
                           rootPC: b.root, bassPC: bassPC, notes: notes,
                           noteNames: names,
                           degrees: degreeLabels,
                           confidence: max(0, min(1, b.score / maxScore)),
                           isInversion: inversion)
    }
}
