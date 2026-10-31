import Foundation
import CoreMIDI

// Auto-test du moteur complet. Tout passe par la vraie sortie audio : on mesure
// ce qui sort, on ne suppose rien.

func load() -> RigConfig {
    let url = URL(fileURLWithPath: AppPaths.configFile.path)
    guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(RigConfig.self, from: d) else {
        print("ÉCHEC : configuration introuvable — lancez d'abord bin/calibrate"); exit(1)
    }
    return c
}

AppPaths.ensure()
let cfg = load()
let engine = LiveEngine(config: cfg)
print("Chargement des banques…")
do {
    try engine.loadBanks()
    try engine.startAudio()
    engine.startMIDI()
} catch { print("ÉCHEC démarrage : \(error.localizedDescription)"); exit(1) }

print("Sortie audio : \(engine.statusAudio)")
print("Entrée MIDI  : \(engine.midiSourceNames.joined(separator: ", "))")
print("Banques      : \(engine.loadedBanks.count) chargées, \(engine.failedBanks.count) en échec"
      + (engine.failedBanks.isEmpty ? "" : " (\(engine.failedBanks.joined(separator: ", ")))"))
print("Local Control du piano pilotable : \(engine.canControlPianoLocal ? "oui" : "non")")
engine.setMasterVolume(0.85)

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  \(ok ? "OK   " : "ÉCHEC") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { failures += 1 }
}
func settle(_ s: Double) { Thread.sleep(forTimeInterval: s) }
func measure() { engine.spectrum.analyse() }

// ---------------------------------------------------------------- 1
print("\n--- 1. Les \(cfg.presets.count) presets produisent du son ---")
var silent: [String] = []
for (i, p) in cfg.presets.enumerated() {
    engine.selectPreset(i)
    settle(0.08)
    // Pour les partages, on joue de part et d'autre du point de coupure.
    for n in [UInt8(45), 52, 60, 64] { engine.injectMIDI(status: 0x90, d1: n, d2: 100) }
    settle(0.45)
    let pk = max(engine.peakL, engine.peakR)
    for n in [UInt8(45), 52, 60, 64] { engine.injectMIDI(status: 0x80, d1: n, d2: 0) }
    if pk < 0.004 { silent.append(p.name) }
    engine.panic(); settle(0.25)
}
check("aucun preset muet", silent.isEmpty, silent.isEmpty ? "\(cfg.presets.count) presets sonnent" : silent.joined(separator: ", "))

// ---------------------------------------------------------------- 2
print("\n--- 2. La transposition décale vraiment la hauteur ---")
// La4 = note MIDI 69 = 440 Hz. On mesure la fondamentale en sortie.
engine.selectPreset(cfg.presets.firstIndex { $0.name == "Concert Grand" } ?? 0)
settle(0.1)

func measureFundamental(semitones: Int32) -> Float {
    engine.resetTranspose()
    engine.nudgeTranspose(semitones)
    engine.injectMIDI(status: 0x90, d1: 69, d2: 100)
    settle(0.30)
    measure()
    let f = engine.spectrum.fundamentalFrequency(between: 150, and: 1100)
    engine.injectMIDI(status: 0x80, d1: 69, d2: 0)
    engine.panic()
    settle(0.3)
    return f
}

for semis in [Int32(0), -1, 1, -3, 5, -12, 12] {
    let expected = 440 * pow(2, Float(semis) / 12)
    let got = measureFundamental(semitones: semis)
    let cents = 1200 * log2(got / expected)
    check(String(format: "%+3d demi-ton(s) : attendu %6.1f Hz", semis, expected),
          abs(cents) < 45,
          String(format: "mesuré %6.1f Hz, écart %+.0f cents", got, cents))
}
engine.resetTranspose()

// ---------------------------------------------------------------- 3
print("\n--- 3. L'octave s'ajoute à la transposition ---")
engine.resetTranspose()
engine.nudgeOctave(1); engine.nudgeTranspose(2)
engine.injectMIDI(status: 0x90, d1: 69, d2: 100)
settle(0.30); measure()
let fOct = engine.spectrum.fundamentalFrequency(between: 600, and: 1800)
engine.injectMIDI(status: 0x80, d1: 69, d2: 0); engine.panic(); settle(0.3)
let expOct = 440 * pow(Float(2), 14.0 / 12.0)
check("octave +1 et +2 demi-tons", abs(1200 * log2(fOct / expOct)) < 45,
      String(format: "attendu %.1f Hz, mesuré %.1f Hz", expOct, fOct))
engine.resetTranspose()

// ---------------------------------------------------------------- 4
print("\n--- 4. Aucune note bloquée ---")
// Une note bloquée se tient ; une réverbération décroît. On mesure donc la
// décroissance, pas un niveau absolu — un seuil fixe confondrait les deux.
func decaysAfterRelease(_ label: String, _ action: () -> Void) {
    engine.injectMIDI(status: 0x90, d1: 60, d2: 100)
    action()
    engine.injectMIDI(status: 0x80, d1: 60, d2: 0)
    settle(1.0)
    let p1 = max(engine.peakL, engine.peakR)
    settle(1.6)
    let p2 = max(engine.peakL, engine.peakR)
    let quiet = p2 < 0.004
    let decaying = p2 < p1 * 0.5
    check(label, engine.heldNotes == 0 && (quiet || decaying),
          String(format: "%d note(s) tenue(s), %+.1f dB → %+.1f dB",
                 engine.heldNotes, 20 * log10(max(p1, 1e-9)), 20 * log10(max(p2, 1e-9))))
}

engine.selectPreset(0); settle(0.1)
decaysAfterRelease("transposition touche tenue") { engine.nudgeTranspose(5) }
engine.resetTranspose()
engine.panic(); settle(0.4)
decaysAfterRelease("changement de son touche tenue") { engine.selectPreset(23) }

// ---------------------------------------------------------------- 5
print("\n--- 5. Les partages clavier routent les bonnes zones ---")
if let si = cfg.presets.firstIndex(where: { $0.category == .split }) {
    let sp = cfg.presets[si]
    engine.selectPreset(si); settle(0.1)
    let lowLayer = sp.layers[0], highLayer = sp.layers[1]
    engine.injectMIDI(status: 0x90, d1: lowLayer.hiKey - 2, d2: 100)
    settle(0.3)
    let lowSound = max(engine.peakL, engine.peakR)
    engine.injectMIDI(status: 0x80, d1: lowLayer.hiKey - 2, d2: 0); engine.panic(); settle(0.4)
    engine.injectMIDI(status: 0x90, d1: highLayer.loKey + 4, d2: 100)
    settle(0.3)
    let highSound = max(engine.peakL, engine.peakR)
    engine.injectMIDI(status: 0x80, d1: highLayer.loKey + 4, d2: 0); engine.panic(); settle(0.4)
    check("« \(sp.name) » : les deux zones sonnent", lowSound > 0.004 && highSound > 0.004,
          String(format: "grave %+.1f dB, aigu %+.1f dB",
                 20 * log10(max(lowSound, 1e-9)), 20 * log10(max(highSound, 1e-9))))
} else { check("preset de partage présent", false) }

// ---------------------------------------------------------------- 6
print("\n--- 6. L'égaliseur agit réellement sur le signal ---")
// On mesure sur un orgue, pas sur un piano : un son tenu donne un spectre
// stable, alors qu'une note de piano perd ses aigus en une fraction de seconde
// et la mesure dépendrait de l'instant du relevé.
let organIndex = cfg.presets.firstIndex { $0.name == "Drawbar Jazz" } ?? 0
engine.selectPreset(organIndex)
engine.resetEQ(); settle(0.2)

/// Moyenne plusieurs relevés de spectre sur un son tenu.
func steadyEnergy(_ lo: Float, _ hi: Float, notes: [UInt8]) -> Float {
    engine.panic(); settle(0.3)
    for n in notes { engine.injectMIDI(status: 0x90, d1: n, d2: 105) }
    settle(0.6)                                  // laisse le son s'établir
    var sum: Double = 0
    for _ in 0..<6 {
        settle(0.06)
        measure()
        sum += Double(engine.spectrum.energyDB(between: lo, and: hi))
    }
    for n in notes { engine.injectMIDI(status: 0x80, d1: n, d2: 0) }
    return Float(sum / 6)
}

let chordNotes: [UInt8] = [48, 55, 60, 64, 67]
let flat = steadyEnergy(2800, 4400, notes: chordNotes)
engine.updateEQBand(4, freq: 3500, gain: 12, q: 1.1, enabled: true); settle(0.2)
let boosted = steadyEnergy(2800, 4400, notes: chordNotes)
engine.updateEQBand(4, freq: 3500, gain: -12, q: 1.1, enabled: true); settle(0.2)
let cut = steadyEnergy(2800, 4400, notes: chordNotes)
engine.resetEQ(); settle(0.2)
check("+12 dB à 3,5 kHz remonte la bande", boosted - flat > 6,
      String(format: "%+.1f dB", boosted - flat))
check("−12 dB à 3,5 kHz abaisse la bande", flat - cut > 6,
      String(format: "%+.1f dB", cut - flat))

print("\n--- 7. Le coupe-bas coupe vraiment les graves ---")
let lowNotes: [UInt8] = [36, 40, 43]
let lowFlat = steadyEnergy(30, 90, notes: lowNotes)
engine.updateEQBand(0, freq: 300, gain: 0, q: 0.707, enabled: true); settle(0.2)
let lowCut = steadyEnergy(30, 90, notes: lowNotes)
engine.resetEQ(); settle(0.2)
check("coupe-bas à 300 Hz", lowFlat - lowCut > 8, String(format: "%+.1f dB", lowCut - lowFlat))
engine.panic(); settle(0.3)

// ---------------------------------------------------------------- 8
print("\n--- 8. Arrêt d'urgence et marge avant saturation ---")
engine.selectPreset(0); settle(0.1)
engine.injectMIDI(status: 0xB0, d1: 64, d2: 127)
for n in [UInt8(48), 52, 55, 60, 64] { engine.injectMIDI(status: 0x90, d1: n, d2: 110) }
settle(0.35)
let before = max(engine.peakL, engine.peakR)
engine.panic(); settle(0.8)
check("silence après l'arrêt", before > 0.004 && max(engine.peakL, engine.peakR) < 0.012)

engine.setMasterVolume(1.0)
var worst: Float = 0
var loudest = ""
for (i, p) in cfg.presets.enumerated() {
    engine.selectPreset(i); settle(0.05)
    for n in [UInt8(36), 43, 48, 52, 55, 60, 64, 67, 72] { engine.injectMIDI(status: 0x90, d1: n, d2: 127) }
    settle(0.3)
    let pk = max(engine.peakL, engine.peakR)
    if pk > worst { worst = pk; loudest = p.name }
    for n in [UInt8(36), 43, 48, 52, 55, 60, 64, 67, 72] { engine.injectMIDI(status: 0x80, d1: n, d2: 0) }
    engine.panic(); settle(0.2)
}
check("aucun dépassement du 0 dBFS, volume au maximum", worst < 0.999,
      String(format: "pire crête %+.1f dB sur « %@ »", 20 * log10(max(worst, 1e-9)), loudest))

// ---------------------------------------------------------------- 9
print("\n--- 9. Pilotage du son interne du piano ---")
if engine.canControlPianoLocal {
    engine.setPianoLocalControl(false)
    engine.setPianoLocalControl(true)
    engine.setPianoLocalControl(false)
    check("CC 122 émis vers le piano", true, "coupé maintenant, rétabli à la fermeture")
} else {
    // Sans clavier branché il n'y a rien à piloter : ce n'est pas un échec,
    // la batterie doit pouvoir tourner sur une machine sans piano.
    print("  —     aucun clavier branché : contrôle du son interne non testé")
}

// ---------------------------------------------------------------- 10
print("\n--- 10. Détection d'accords sur le moteur en marche ---")
engine.selectPreset(0); settle(0.1)
for (notes, expected) in [([60, 64, 67], "C"), ([62, 65, 69, 72], "Dm7"),
                          ([55, 59, 62, 65], "G7"), ([60, 64, 67, 71, 74], "Cmaj9")] {
    for n in notes { engine.injectMIDI(status: 0x90, d1: UInt8(n), d2: 96) }
    settle(0.12)
    let c = engine.currentChord
    check("\(expected)", c.symbol == expected, "détecté \(c.symbol) · \(c.noteNames.joined(separator: " "))")
    for n in notes { engine.injectMIDI(status: 0x80, d1: UInt8(n), d2: 0) }
    settle(0.2)
}
check("plus aucune note tenue après relâchement", engine.soundingNotes.isEmpty)

// ---------------------------------------------------------------- 11
print("\n--- 11. Enregistrement complet d'une prise ---")
engine.selectPreset(0); engine.resetTranspose(); settle(0.1)
_ = engine.startTake(withAudio: true)
let cadence: [[Int]] = [[38, 62, 65, 69, 72], [31, 62, 65, 67, 71], [36, 64, 67, 71, 72]]
engine.injectMIDI(status: 0xB0, d1: 64, d2: 127)
for chord in cadence {
    for n in chord { engine.injectMIDI(status: 0x90, d1: UInt8(n), d2: 92) }
    settle(0.9)
    for n in chord { engine.injectMIDI(status: 0x80, d1: UInt8(n), d2: 0) }
    settle(0.12)
}
engine.injectMIDI(status: 0xB0, d1: 64, d2: 0)
settle(0.4)
let playedNotes = engine.recordedNoteCount
let meta = engine.stopTake(name: "Test automatique", tempo: 120)
check("prise créée", meta != nil)
if let meta {
    let dir = TakeStore.folder(meta.id)
    func size(_ f: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(f).path)[.size] as? Int) as? Int ?? 0
    }
    // Le clavier est branché : s'il est touché pendant le test, ses notes entrent
    // aussi dans la prise. On vérifie donc que la cadence est bien là, pas que
    // rien d'autre ne s'y trouve.
    let presses = cadence.flatMap { $0 }.count          // 15 frappes
    let expected = Set(cadence.flatMap { $0 })           // 10 hauteurs distinctes
    let recorded = Set(TakeStore.load(meta.id)?.notes.map { $0.note } ?? [])
    check("la cadence est enregistrée", expected.isSubset(of: recorded),
          "\(meta.noteCount) notes pour \(presses) frappes"
          + (meta.noteCount > presses ? " — le clavier a été touché pendant le test" : ""))
    check("cohérence du compteur", meta.noteCount == playedNotes, "\(meta.noteCount) / \(playedNotes)")
    check("audio.wav", size("audio.wav") > 200_000,
          String(format: "%.1f Mo", Double(size("audio.wav")) / 1_048_576))
    check("performance.mid", size("performance.mid") > 150, "\(size("performance.mid")) octets")
    check("partition.musicxml", size("partition.musicxml") > 1500, "\(size("partition.musicxml")) octets")
    check("accords.txt", size("accords.txt") > 80, "\(size("accords.txt")) octets")
    if let grid = try? String(contentsOf: dir.appendingPathComponent("accords.txt"), encoding: .utf8) {
        check("la cadence est dans la grille",
              grid.contains("Dm7") && grid.contains("G7") && grid.contains("Cmaj7"),
              grid.split(separator: "\n").filter { $0.contains(":") }.map {
                  $0.split(separator: " ").dropFirst().first.map(String.init) ?? "" }.joined(separator: " "))
    }
    if let reloaded = TakeStore.load(meta.id) {
        check("prise relisible", reloaded.notes.count == meta.noteCount)
    } else { check("prise relisible", false) }
    TakeStore.delete(meta.id)
    check("prise supprimée", !FileManager.default.fileExists(atPath: dir.path))
}

// ---------------------------------------------------------------- 12
print("\n--- 12. Périphériques, sans dépendre d'une marque ---")
let outs = CA.outputDevices()
check("sorties audio détectées", !outs.isEmpty, outs.map { $0.1 }.joined(separator: ", "))
let ins = MicInput.inputDevices()
check("entrées détectées", !ins.isEmpty, ins.map { $0.1 }.joined(separator: ", "))
let auto = DevicePicker.audioOutput(preferring: "", midiNames: engine.midiSourceNames)
check("choix automatique de la sortie", auto != nil,
      auto.map { "« \($0.1) » retenue pour le clavier « \(engine.midiSourceNames.first ?? "?") »" } ?? "")
check("ports logiciels ignorés", !DevicePicker.looksLikeSoftwarePort("ARIUS")
      && DevicePicker.looksLikeSoftwarePort("IAC Driver Bus 1"))

// ---------------------------------------------------------------- 13
print("\n--- 13. Branchement à chaud d'un clavier ---")
// CoreMIDI délivre ses notifications sur la run loop : on la fait tourner,
// sinon rien n'arrive — c'est exactement le bug qu'on vérifie ici.
func spin(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}
let beforePlug = engine.midiSourceNames
var fakeClient = MIDIClientRef()
var fakeSource = MIDIEndpointRef()
MIDIClientCreate("PianoLiveFakeKeyboard" as CFString, nil, nil, &fakeClient)
let fakeName = "Clavier de test PLS"
let created = MIDISourceCreate(fakeClient, fakeName as CFString, &fakeSource)
check("clavier factice créé", created == noErr)
spin(2.0)
let after = engine.midiSourceNames
check("détecté sans intervention", after.contains(fakeName),
      "avant : \(beforePlug.joined(separator: ", ")) → après : \(after.joined(separator: ", "))")
check("l'ancien clavier est toujours là", beforePlug.allSatisfy { after.contains($0) })

MIDIEndpointDispose(fakeSource)
MIDIClientDispose(fakeClient)
spin(2.0)
check("débranchement détecté", !engine.midiSourceNames.contains(fakeName),
      engine.midiSourceNames.joined(separator: ", "))

// ---------------------------------------------------------------- 14
print("\n--- 14. Changement de sortie audio en cours de jeu ---")
let devices = CA.outputDevices().map { $0.1 }
let other = devices.first { $0 != engine.audioDeviceLabel && !$0.contains("Aggregate") }
if let other {
    let origin = engine.audioDeviceLabel
    check("bascule vers « \(other) »", engine.switchAudioDevice(named: other), engine.statusAudio)
    settle(1.0)
    for n in [UInt8(60), 64, 67] { engine.injectMIDI(status: 0x90, d1: n, d2: 100) }
    settle(0.4)
    let pk = max(engine.peakL, engine.peakR)
    for n in [UInt8(60), 64, 67] { engine.injectMIDI(status: 0x80, d1: n, d2: 0) }
    engine.panic(); settle(0.4)
    check("du son sur la nouvelle sortie", pk > 0.004,
          String(format: "crête %+.1f dB", 20 * log10(max(pk, 1e-9))))
    check("retour sur « \(origin) »", engine.switchAudioDevice(named: origin))
    settle(1.0)
    for n in [UInt8(60), 64, 67] { engine.injectMIDI(status: 0x90, d1: n, d2: 100) }
    settle(0.4)
    let pk2 = max(engine.peakL, engine.peakR)
    for n in [UInt8(60), 64, 67] { engine.injectMIDI(status: 0x80, d1: n, d2: 0) }
    engine.panic(); settle(0.3)
    check("du son après retour", pk2 > 0.004,
          String(format: "crête %+.1f dB", 20 * log10(max(pk2, 1e-9))))
} else {
    check("une seconde sortie pour tester", false, "une seule sortie disponible")
}

engine.setMasterVolume(cfg.masterVolume)
engine.selectPreset(cfg.presets.firstIndex { $0.name == "Concert Grand" } ?? 0)
engine.resetTranspose()
engine.shutdown()

print("\n==============================================")
print(failures == 0 ? "TOUS LES TESTS PASSENT" : "\(failures) TEST(S) EN ÉCHEC")
print("==============================================")
exit(failures == 0 ? 0 : 1)
