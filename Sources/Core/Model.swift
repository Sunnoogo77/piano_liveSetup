import Foundation

// MARK: - Emplacements

/// Tout vit dans un seul dossier, ~/Musique/Piano Live Setup par défaut.
/// PIANO_LIVE_HOME permet de le déplacer — utile pour tester une installation
/// propre sans toucher à celle qui sert sur scène.
enum AppPaths {
    static var home: URL {
        if let p = ProcessInfo.processInfo.environment["PIANO_LIVE_HOME"], !p.isEmpty {
            return URL(fileURLWithPath: NSString(string: p).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSString(string: "~/Music/Piano Live Setup").expandingTildeInPath)
    }
    static var sounds: URL      { home.appendingPathComponent("Sounds") }
    static var configFile: URL  { home.appendingPathComponent("Config/setup.json") }
    static var recordings: URL  { home.appendingPathComponent("Enregistrements") }

    static func ensure() {
        for d in [sounds, configFile.deletingLastPathComponent(), recordings] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Banques

struct BankRef: Codable, Hashable {
    var file: String        // nom du fichier dans Sounds/
    var sfBank: Int32       // banque interne SF2
    var program: Int32
}

enum Bank {
    static let salamander = "SalamanderGrandPiano.sf2"
    static let ydp        = "YDP-GrandPiano.sf2"
    static let gu         = "GeneralUser-GS.sf2"
    static let ms         = "MuseScore_General.sf3"
    static let orgDrawbar = "Organ-Drawbar.sf2"
    static let orgPerc    = "Organ-Percussive.sf2"
    static let orgRock    = "Organ-Rock.sf2"
    static let orgChurch  = "Organ-Church.sf2"
    static let padChoir   = "Pad-Choir.sf2"
    static let padSweep   = "Pad-Sweep.sf2"
    static let padNewAge  = "Pad-NewAge.sf2"
    static let padBowed   = "Pad-Bowed.sf2"
    static let strings1   = "Strings-1.sf2"
    static let strings2   = "Strings-2.sf2"
    static let fm1        = "FM-Piano1.sf2"
    static let fm2        = "FM-Piano2.sf2"

    /// Ordre de chargement : les banques les plus utilisées d'abord.
    static let all = [salamander, gu, ms, ydp,
                      orgDrawbar, orgPerc, orgRock, orgChurch,
                      padChoir, padSweep, padNewAge, padBowed,
                      strings1, strings2, fm1, fm2]

    /// Remplacement quand une banque n'est pas installée : soit un fichier
    /// équivalent qui garde le même numéro de programme (les banques GM ont la
    /// même numérotation), soit un programme précis d'une banque générale.
    enum Fallback {
        case keepProgram(String)
        case fixed(String, Int32, Int32)
    }

    /// Chaînes d'équivalence. Une installation allégée reste jouable :
    /// aucun preset ne devient muet, il sonne seulement moins bien.
    static let fallbacks: [String: [Fallback]] = [
        salamander: [.keepProgram(ydp), .keepProgram(ms), .keepProgram(gu)],
        ydp:        [.keepProgram(salamander), .keepProgram(ms), .keepProgram(gu)],
        ms:         [.keepProgram(gu)],
        gu:         [.keepProgram(ms)],
        orgDrawbar: [.fixed(ms, 0, 16), .fixed(gu, 0, 16)],
        orgPerc:    [.fixed(ms, 0, 17), .fixed(gu, 0, 17)],
        orgRock:    [.fixed(ms, 0, 18), .fixed(gu, 0, 18)],
        orgChurch:  [.fixed(ms, 0, 19), .fixed(gu, 0, 19)],
        padChoir:   [.fixed(ms, 0, 52), .fixed(gu, 0, 52)],
        padSweep:   [.fixed(ms, 0, 95), .fixed(gu, 0, 95)],
        padNewAge:  [.fixed(ms, 0, 88), .fixed(gu, 0, 88)],
        padBowed:   [.fixed(ms, 0, 92), .fixed(gu, 0, 92)],
        strings1:   [.fixed(ms, 0, 50), .fixed(gu, 0, 50)],
        strings2:   [.fixed(ms, 0, 51), .fixed(gu, 0, 51)],
        fm1:        [.fixed(ms, 0, 5),  .fixed(gu, 0, 5)],
        fm2:        [.fixed(ms, 8, 5),  .fixed(gu, 8, 5)],
    ]

    /// Les deux banques sans lesquelles rien ne tourne.
    static let essential = [gu, ms]

    static let credits: [String: String] = [
        salamander: "Salamander Grand Piano — Alexander Holm, CC BY 3.0 (FreePats)",
        ydp:        "YDP Grand Piano — Zenph Studios / FreePats, CC BY 3.0",
        gu:         "GeneralUser GS 2.0.3 — S. Christian Collins, licence libre",
        ms:         "MuseScore General — S. Christian Collins, MIT",
        orgDrawbar: "Drawbar Organ Emulation — FreePats, CC0",
        orgPerc:    "Percussive Organ Emulation — FreePats, CC0",
        orgRock:    "Rock Organ Emulation — FreePats, CC0",
        orgChurch:  "Church Organ Emulation — FreePats, CC0",
        padChoir:   "Synth Pad Choir — FreePats, CC0",
        padSweep:   "Sweep Pad — FreePats, CC0",
        padNewAge:  "New Age Pad — FreePats, CC0",
        padBowed:   "Synth Pad Bowed — FreePats, CC0",
        strings1:   "Synth Strings 1 — FreePats, CC0",
        strings2:   "Synth Strings 2 — FreePats, CC0",
        fm1:        "FM Piano 1 — FreePats, CC0",
        fm2:        "FM Piano 2 — FreePats, CC0",
    ]
}

/// Trouve la banque réellement disponible pour une couche : celle qui est
/// demandée, sinon son équivalent le plus proche. Partagé par le moteur et
/// par l'outil d'étalonnage, pour qu'ils voient exactement les mêmes sons.
struct BankResolver {
    let sfIDs: [String: Int32]

    struct Resolved { var id: Int32; var bank: Int32; var program: Int32; var file: String }

    func resolve(_ ref: BankRef) -> Resolved? {
        if let id = sfIDs[ref.file] {
            return Resolved(id: id, bank: ref.sfBank, program: ref.program, file: ref.file)
        }
        for alt in Bank.fallbacks[ref.file] ?? [] {
            switch alt {
            case .keepProgram(let file):
                if let id = sfIDs[file] {
                    return Resolved(id: id, bank: ref.sfBank, program: ref.program, file: file)
                }
            case .fixed(let file, let b, let p):
                if let id = sfIDs[file] { return Resolved(id: id, bank: b, program: p, file: file) }
            }
        }
        return nil
    }
}

// MARK: - Couches

struct Layer: Codable, Hashable {
    var bank: BankRef
    var volume: Float = 1          // 0…1
    var pan: Float = 0             // −1…1
    var semitones: Int32 = 0       // décalage propre à la couche
    var loKey: UInt8 = 0
    var hiKey: UInt8 = 127
    var loVel: UInt8 = 1
    var hiVel: UInt8 = 127
    var reverb: Int32 = 24         // CC91
    var chorus: Int32 = 0          // CC93

    var isSplit: Bool { loKey > 0 || hiKey < 127 }
}

// MARK: - Égaliseur

struct EQBand: Codable, Hashable {
    var kind: FilterKind
    var freq: Float
    var gain: Float
    var q: Float
    var enabled: Bool

    var label: String {
        switch kind {
        case .highPass:  return "HPF"
        case .lowShelf:  return "GRAVE"
        case .peaking:   return freq < 700 ? "BAS-MÉD" : (freq < 2500 ? "MÉDIUM" : "PRÉSENCE")
        case .highShelf: return "AIGU"
        case .lowPass:   return "LPF"
        }
    }
}

/// Les sept bandes ont des rôles fixes, comme une tranche de console.
func defaultEQ() -> [EQBand] {
    [
        EQBand(kind: .highPass,  freq: 28,    gain: 0, q: 0.707, enabled: true),
        EQBand(kind: .lowShelf,  freq: 120,   gain: 0, q: 0.707, enabled: true),
        EQBand(kind: .peaking,   freq: 350,   gain: 0, q: 1.0,   enabled: true),
        EQBand(kind: .peaking,   freq: 1200,  gain: 0, q: 1.0,   enabled: true),
        EQBand(kind: .peaking,   freq: 3500,  gain: 0, q: 1.1,   enabled: true),
        EQBand(kind: .highShelf, freq: 8000,  gain: 0, q: 0.707, enabled: true),
        EQBand(kind: .lowPass,   freq: 19000, gain: 0, q: 0.707, enabled: false),
    ]
}

/// Réglage de départ pour une voix : coupe-bas haut placé, bas-médium dégagé,
/// présence légère. Point de départ classique en sonorisation.
func micDefaultEQ() -> [EQBand] {
    [
        EQBand(kind: .highPass,  freq: 95,    gain: 0,    q: 0.707, enabled: true),
        EQBand(kind: .lowShelf,  freq: 180,   gain: -1.5, q: 0.707, enabled: true),
        EQBand(kind: .peaking,   freq: 320,   gain: -3.0, q: 1.2,   enabled: true),
        EQBand(kind: .peaking,   freq: 1500,  gain: 1.0,  q: 1.0,   enabled: true),
        EQBand(kind: .peaking,   freq: 4000,  gain: 2.5,  q: 1.1,   enabled: true),
        EQBand(kind: .highShelf, freq: 9000,  gain: 1.5,  q: 0.707, enabled: true),
        EQBand(kind: .lowPass,   freq: 16000, gain: 0,    q: 0.707, enabled: true),
    ]
}

func eq(_ edits: [(Int, Float, Float)] = [], hpf: Float? = nil, lpf: Float? = nil) -> [EQBand] {
    var b = defaultEQ()
    if let hpf { b[0].freq = hpf }
    if let lpf { b[6].freq = lpf; b[6].enabled = true }
    for (i, f, g) in edits { b[i].freq = f; b[i].gain = g }
    return b
}

// MARK: - Preset

enum Category: String, Codable, CaseIterable {
    case acoustic  = "Pianos acoustiques"
    case electric  = "Pianos électriques"
    case organ     = "Orgues"
    case pad       = "Nappes & cordes"
    case layered   = "Superpositions"
    case split     = "Partages clavier"

    var short: String {
        switch self {
        case .acoustic: return "Acoustique"
        case .electric: return "Électrique"
        case .organ:    return "Orgue"
        case .pad:      return "Nappe"
        case .layered:  return "Superposé"
        case .split:    return "Partage"
        }
    }
    var symbol: String {
        switch self {
        case .acoustic: return "pianokeys"
        case .electric: return "bolt.fill"
        case .organ:    return "pipe.and.drop.fill"
        case .pad:      return "waveform.path"
        case .layered:  return "square.stack.3d.up.fill"
        case .split:    return "rectangle.split.2x1.fill"
        }
    }
}

struct Preset: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var subtitle: String
    var category: Category
    var layers: [Layer]
    var eqBands: [EQBand] = defaultEQ()
    var drive: Float = 0
    var tremRate: Float = 0
    var tremDepth: Float = 0
    var compAmount: Float = 0
    var velocityGamma: Float = 1.0     // <1 : plus facile de jouer fort
    var gain: Float = 1.0              // étalonné automatiquement
    var layerMix: Float = 1.0          // niveau relatif de la couche d'accompagnement

    var hasSecondLayer: Bool { layers.count > 1 }
}

// MARK: - Bibliothèque

enum Library {
    static func L(_ file: String, _ bank: Int32 = 0, _ prog: Int32 = 0,
                  vol: Float = 1, pan: Float = 0, semi: Int32 = 0,
                  lo: UInt8 = 0, hi: UInt8 = 127, rev: Int32 = 24, cho: Int32 = 0) -> Layer {
        Layer(bank: BankRef(file: file, sfBank: bank, program: prog),
              volume: vol, pan: pan, semitones: semi,
              loKey: lo, hiKey: hi, reverb: rev, chorus: cho)
    }

    static func all() -> [Preset] {
        var p: [Preset] = []

        // ---------- Pianos acoustiques ----------
        p.append(Preset(name: "Concert Grand", subtitle: "Yamaha C5, 16 couches de vélocité",
                        category: .acoustic, layers: [L(Bank.salamander, rev: 26)],
                        eqBands: eq(hpf: 28)))

        p.append(Preset(name: "Soft Ballad", subtitle: "Doux, chaud, réverbération ample",
                        category: .acoustic, layers: [L(Bank.salamander, rev: 46)],
                        eqBands: eq([(1, 150, 1.8), (4, 3500, -1.5), (5, 7000, -3.0)], hpf: 30),
                        velocityGamma: 0.82))

        p.append(Preset(name: "Stage Bright", subtitle: "Percute, taillé pour la scène",
                        category: .acoustic, layers: [L(Bank.salamander, rev: 18)],
                        eqBands: eq([(2, 320, -1.5), (4, 3800, 2.8), (5, 9000, 2.0)], hpf: 55),
                        compAmount: 0.25))

        p.append(Preset(name: "Pop Piano", subtitle: "Bas-médium dégagé, pour chanter dessus",
                        category: .acoustic, layers: [L(Bank.salamander, rev: 20)],
                        eqBands: eq([(2, 380, -3.0), (4, 5000, 3.2), (5, 10000, 1.5)], hpf: 85),
                        compAmount: 0.4))

        p.append(Preset(name: "Disklavier", subtitle: "Yamaha Disklavier Pro, droit et net",
                        category: .acoustic, layers: [L(Bank.ydp, rev: 28)],
                        eqBands: eq(hpf: 30)))

        p.append(Preset(name: "Mellow Grand", subtitle: "Feutré, jazz de salon",
                        category: .acoustic, layers: [L(Bank.ms, 8, 0, rev: 34)],
                        eqBands: eq([(1, 160, 2.0), (5, 6500, -4.0)], hpf: 32, lpf: 11000),
                        velocityGamma: 0.9))

        // ---------- Pianos électriques ----------
        p.append(Preset(name: "Tine Classic", subtitle: "Rhodes à lamelles, net",
                        category: .electric, layers: [L(Bank.ms, 0, 4, rev: 22)],
                        eqBands: eq([(1, 140, 1.2), (4, 3200, 1.5)], hpf: 45)))

        p.append(Preset(name: "Suitcase Tremolo", subtitle: "Trémolo stéréo, le son 70s",
                        category: .electric, layers: [L(Bank.gu, 0, 4, rev: 26)],
                        eqBands: eq([(1, 150, 2.0), (4, 3000, 1.0)], hpf: 45),
                        tremRate: 5.2, tremDepth: 0.5))

        p.append(Preset(name: "Dyno Bright", subtitle: "Chorus et cloche, très présent",
                        category: .electric, layers: [L(Bank.gu, 8, 4, rev: 24, cho: 40)],
                        eqBands: eq([(4, 4200, 4.0), (5, 9000, 2.5)], hpf: 55)))

        p.append(Preset(name: "Wurly Drive", subtitle: "Mordant, légèrement saturé",
                        category: .electric, layers: [L(Bank.gu, 0, 5, rev: 20)],
                        eqBands: eq([(2, 400, -2.0), (3, 1600, 3.0), (5, 8000, -2.0)], hpf: 110),
                        drive: 0.35, tremRate: 6.4, tremDepth: 0.3, compAmount: 0.3))

        p.append(Preset(name: "FM Digital", subtitle: "Cloche numérique, esprit DX",
                        category: .electric, layers: [L(Bank.fm1, rev: 24, cho: 24)],
                        eqBands: eq([(4, 4500, 2.0)], hpf: 50)))

        p.append(Preset(name: "FM Mellow", subtitle: "FM adouci, nappe de fond",
                        category: .electric, layers: [L(Bank.fm2, rev: 34, cho: 32)],
                        eqBands: eq([(1, 180, 1.5)], hpf: 45, lpf: 7000)))

        // ---------- Orgues ----------
        p.append(Preset(name: "Drawbar Jazz", subtitle: "Roues phoniques, propre",
                        category: .organ, layers: [L(Bank.orgDrawbar, rev: 20)],
                        eqBands: eq([(3, 1400, 1.5)], hpf: 55), drive: 0.12))

        p.append(Preset(name: "Percussive", subtitle: "Attaque marquée, troisième harmonique",
                        category: .organ, layers: [L(Bank.orgPerc, rev: 20)],
                        eqBands: eq([(4, 3000, 2.0)], hpf: 55), drive: 0.15))

        p.append(Preset(name: "Rock Drive", subtitle: "Saturé, pour les refrains",
                        category: .organ, layers: [L(Bank.orgRock, rev: 18)],
                        eqBands: eq([(3, 2000, 3.0), (5, 8000, 1.5)], hpf: 70),
                        drive: 0.45, compAmount: 0.3))

        p.append(Preset(name: "Full Church", subtitle: "Jeu plein, réverbération de nef",
                        category: .organ, layers: [L(Bank.orgChurch, rev: 60)],
                        eqBands: eq([(1, 110, 1.5)], hpf: 32)))

        p.append(Preset(name: "Gospel Leslie", subtitle: "Désaccordé, rotation lente",
                        category: .organ, layers: [L(Bank.gu, 8, 16, rev: 26)],
                        eqBands: eq([(3, 1600, 2.0)], hpf: 60),
                        drive: 0.28, tremRate: 5.8, tremDepth: 0.42))

        // ---------- Nappes & cordes ----------
        p.append(Preset(name: "Warm Pad", subtitle: "Nappe douce et enveloppante",
                        category: .pad, layers: [L(Bank.ms, 0, 89, rev: 60)],
                        eqBands: eq(hpf: 60, lpf: 9000)))

        p.append(Preset(name: "Choir Pad", subtitle: "Voix de synthèse, souffle",
                        category: .pad, layers: [L(Bank.padChoir, rev: 64)],
                        eqBands: eq([(2, 400, -2.0)], hpf: 80)))

        p.append(Preset(name: "Bowed Glass", subtitle: "Archet et verre, cinématique",
                        category: .pad, layers: [L(Bank.padBowed, rev: 66)],
                        eqBands: eq(hpf: 70)))

        p.append(Preset(name: "Sweep Pad", subtitle: "Filtre qui respire",
                        category: .pad, layers: [L(Bank.padSweep, rev: 58)],
                        eqBands: eq(hpf: 70)))

        p.append(Preset(name: "New Age", subtitle: "Cloche et nappe mêlées",
                        category: .pad, layers: [L(Bank.padNewAge, rev: 56)],
                        eqBands: eq(hpf: 60)))

        p.append(Preset(name: "Slow Strings", subtitle: "Cordes à attaque lente",
                        category: .pad, layers: [L(Bank.ms, 0, 49, rev: 54)],
                        eqBands: eq([(1, 150, 1.0)], hpf: 60)))

        // ---------- Superpositions ----------
        p.append(Preset(name: "Grand + Soft Pad", subtitle: "Piano devant, nappe discrète",
                        category: .layered,
                        layers: [L(Bank.salamander, rev: 26),
                                 L(Bank.ms, 0, 89, vol: 0.30, rev: 62)],
                        eqBands: eq(hpf: 30), layerMix: 0.30))

        p.append(Preset(name: "Grand + Strings", subtitle: "Piano et cordes lentes",
                        category: .layered,
                        layers: [L(Bank.salamander, rev: 26),
                                 L(Bank.ms, 0, 49, vol: 0.28, rev: 58)],
                        eqBands: eq(hpf: 30), layerMix: 0.28))

        p.append(Preset(name: "Grand + Choir", subtitle: "Piano et chœur, pour les ballades",
                        category: .layered,
                        layers: [L(Bank.salamander, rev: 28),
                                 L(Bank.padChoir, vol: 0.26, rev: 66)],
                        eqBands: eq(hpf: 32), layerMix: 0.26))

        p.append(Preset(name: "Cinematic Piano", subtitle: "Piano et archets, très ample",
                        category: .layered,
                        layers: [L(Bank.salamander, rev: 40),
                                 L(Bank.padBowed, vol: 0.34, rev: 70)],
                        eqBands: eq([(5, 9000, 1.5)], hpf: 30), layerMix: 0.34))

        p.append(Preset(name: "EP + Pad", subtitle: "Rhodes posé sur une nappe",
                        category: .layered,
                        layers: [L(Bank.ms, 0, 4, rev: 24),
                                 L(Bank.padSweep, vol: 0.30, rev: 60)],
                        eqBands: eq(hpf: 45), layerMix: 0.30))

        p.append(Preset(name: "Organ + Choir", subtitle: "Orgue soutenu par des voix",
                        category: .layered,
                        layers: [L(Bank.orgDrawbar, rev: 24),
                                 L(Bank.padChoir, vol: 0.26, rev: 64)],
                        eqBands: eq(hpf: 55), drive: 0.12, layerMix: 0.26))

        // ---------- Partages clavier ----------
        p.append(Preset(name: "Basse / Piano", subtitle: "Basse doigtée sous Mi2, piano au-dessus",
                        category: .split,
                        layers: [L(Bank.gu, 0, 33, vol: 0.85, lo: 21, hi: 51, rev: 10),
                                 L(Bank.salamander, lo: 52, hi: 108, rev: 26)],
                        eqBands: eq(hpf: 28), layerMix: 0.85))

        p.append(Preset(name: "Nappe / Piano", subtitle: "Nappe en main gauche, piano en main droite",
                        category: .split,
                        layers: [L(Bank.ms, 0, 89, vol: 0.55, lo: 21, hi: 59, rev: 62),
                                 L(Bank.salamander, lo: 60, hi: 108, rev: 26)],
                        eqBands: eq(hpf: 32), layerMix: 0.55))

        return p
    }
}

// MARK: - Configuration persistée

struct RigConfig: Codable {
    var soundsDir: String
    var presets: [Preset]
    var masterVolume: Float = 0.8
    var audioDeviceName: String = "ARIUS"
    var bufferFrames: UInt32 = 128
    var localControlOff: Bool = true
    var currentPreset: String = "Concert Grand"

    static func defaults() -> RigConfig {
        RigConfig(soundsDir: AppPaths.sounds.path, presets: Library.all())
    }
}
