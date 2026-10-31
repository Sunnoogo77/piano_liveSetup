import Foundation

// Vérifie les trois formats d'export sur une prise fabriquée :
// une cadence II-V-I en Do, main gauche et main droite.

func n(_ note: Int, _ start: Double, _ len: Double, _ vel: Int = 88) -> RecNote {
    RecNote(note: note, velocity: vel, start: start, end: start + len)
}

var notes: [RecNote] = []
// Dm7 | G7 | Cmaj7 | Cmaj7 — deux temps chacun à 120 bpm (1 temps = 0,5 s)
let chords: [(Double, [Int], [Int])] = [
    (0.0, [38], [62, 65, 69, 72]),      // Dm7
    (2.0, [31], [62, 65, 67, 71]),      // G7
    (4.0, [36], [64, 67, 71, 72]),      // Cmaj7
    (6.0, [36], [64, 67, 71, 72]),
]
for (t, bass, right) in chords {
    notes.append(n(bass[0], t, 1.9, 70))
    for (i, p) in right.enumerated() { notes.append(n(p, t + Double(i) * 0.02, 1.8)) }
}
let ccs = [RecCC(cc: 64, value: 127, time: 0.05), RecCC(cc: 64, value: 0, time: 7.9)]

let meta = TakeMeta(id: "test", name: "Cadence II-V-I", date: Date(), duration: 8.0,
                    preset: "Concert Grand", transpose: 0, tempo: 120,
                    noteCount: notes.count, hasAudio: false)
let take = Take(meta: meta, notes: notes, ccs: ccs)

var fails = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  \(ok ? "OK   " : "ÉCHEC") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { fails += 1 }
}

print("--- Fichier MIDI ---")
let mid = MIDIFileWriter.data(take: take)
let bytes = [UInt8](mid)
check("en-tête MThd", bytes.starts(with: Array("MThd".utf8)))
check("deux pistes", mid.range(of: Data("MTrk".utf8)) != nil
      && String(decoding: mid, as: UTF8.self).components(separatedBy: "MTrk").count == 3)
check("taille plausible", mid.count > 200 && mid.count < 20000, "\(mid.count) octets")
let outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rectest")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let midURL = outDir.appendingPathComponent("test.mid")
try! mid.write(to: midURL)
check("écrit sur disque", FileManager.default.fileExists(atPath: midURL.path), midURL.path)

print("\n--- Partition MusicXML ---")
let xml = ScoreWriter.musicXML(take: take)
let xmlURL = outDir.appendingPathComponent("test.musicxml")
try! xml.write(to: xmlURL, atomically: true, encoding: .utf8)
check("déclaration XML", xml.hasPrefix("<?xml"))
check("score-partwise", xml.contains("<score-partwise"))
check("deux portées", xml.contains("<staves>2</staves>"))
check("clés sol et fa", xml.contains("<sign>G</sign>") && xml.contains("<sign>F</sign>"))
let measures = xml.components(separatedBy: "<measure number=").count - 1
check("mesures générées", measures >= 2, "\(measures) mesures")
let noteCount = xml.components(separatedBy: "<pitch>").count - 1
check("notes présentes", noteCount >= notes.count, "\(noteCount) notes écrites pour \(notes.count) jouées")
check("tempo noté", xml.contains("<per-minute>120</per-minute>"))

print("\n--- Grille d'accords ---")
let timeline = ChordTimeline.build(notes)
for e in timeline {
    print(String(format: "    %5.2f → %5.2f s   %@  (%@)", e.start, e.end, e.symbol, e.quality))
}
let symbols = timeline.map { $0.symbol }
check("quatre segments d'accord", timeline.count >= 3, "\(timeline.count) segments")
check("la cadence est reconnue",
      symbols.contains("Dm7") && symbols.contains("G7") && symbols.contains("Cmaj7"),
      symbols.joined(separator: " | "))

print("\n--- En-tête WAV ---")
let rec = AudioFileRecorder()
let wavURL = outDir.appendingPathComponent("test.wav")
try! rec.start(url: wavURL, sampleRate: 44100)
var l = [Float](repeating: 0, count: 512), r = [Float](repeating: 0, count: 512)
for blk in 0..<80 {
    for i in 0..<512 {
        let t = Double(blk * 512 + i) / 44100
        l[i] = Float(sin(2 * .pi * 440 * t) * 0.3)
        r[i] = Float(sin(2 * .pi * 554.37 * t) * 0.3)
    }
    l.withUnsafeBufferPointer { lp in r.withUnsafeBufferPointer { rp in
        rec.append(lp.baseAddress!, rp.baseAddress!, frames: 512) } }
    Thread.sleep(forTimeInterval: 0.012)
}
rec.stop()
let size = (try? FileManager.default.attributesOfItem(atPath: wavURL.path)[.size] as? Int) ?? 0
let head = try! FileHandle(forReadingFrom: wavURL).read(upToCount: 44)!
check("signature RIFF/WAVE", String(decoding: head[0..<4], as: UTF8.self) == "RIFF"
      && String(decoding: head[8..<12], as: UTF8.self) == "WAVE")
check("24 bits stéréo 44,1 kHz", head[34] == 24 && head[22] == 2)
check("données écrites", size > 100_000, "\(size ?? 0) octets, \(String(format: "%.2f", Double(size ?? 0) / (44100 * 6))) s")

print("--- Configuration tolérante aux versions ---")
// Une configuration écrite par une version plus ancienne, à qui il manque des
// champs, doit se relire sans perdre ce qu'elle contient.
do {
    var cfg = RigConfig.defaults()
    cfg.masterVolume = 0.42
    cfg.presets[0].gain = 1.234
    cfg.presets[0].eqBands[4].gain = 7.5
    cfg.remoteKey = "ABC123"
    let full = try! JSONEncoder().encode(cfg)
    var obj = try! JSONSerialization.jsonObject(with: full) as! [String: Any]

    // On retire les champs récents, comme le ferait un fichier d'avant.
    for key in ["remoteEnabled", "remotePort", "remoteKey"] { obj.removeValue(forKey: key) }
    var presets = obj["presets"] as! [[String: Any]]
    presets[0].removeValue(forKey: "velocityGamma")
    presets[0].removeValue(forKey: "compAmount")
    obj["presets"] = presets
    let older = try! JSONSerialization.data(withJSONObject: obj)

    if let back = try? JSONDecoder().decode(RigConfig.self, from: older) {
        check("relue sans erreur", true, "\(back.presets.count) presets")
        check("le volume est conservé", abs(back.masterVolume - 0.42) < 0.001)
        check("l'étalonnage est conservé", abs(back.presets[0].gain - 1.234) < 0.001,
              String(format: "gain %.3f", back.presets[0].gain))
        check("les réglages d'égaliseur sont conservés",
              abs(back.presets[0].eqBands[4].gain - 7.5) < 0.001)
        check("les champs absents prennent leur valeur par défaut",
              back.remotePort == 8787 && back.remoteKey.isEmpty
              && abs(back.presets[0].velocityGamma - 1) < 0.001)
    } else {
        check("relue sans erreur", false, "une configuration plus ancienne est rejetée")
    }
}

print("\n--- Analyseur de spectre ---")
#if canImport(Accelerate) && !PLS_PORTABLE
print("  moteur FFT : Accelerate (Apple)")
#else
print("  moteur FFT : Swift pur (portable)")
#endif
let tap = SpectrumTap()
tap.sampleRate = 44100
var sl = [Float](repeating: 0, count: 2048)
var sr = [Float](repeating: 0, count: 2048)
for i in 0..<2048 {
    let t = Double(i) / 44100
    let v = Float(0.5 * sin(2 * .pi * 440 * t) + 0.12 * sin(2 * .pi * 3000 * t))
    sl[i] = v; sr[i] = v
}
sl.withUnsafeBufferPointer { lp in sr.withUnsafeBufferPointer { rp in
    tap.write(lp.baseAddress!, rp.baseAddress!, frames: 2048) } }
tap.analyse()
let f0 = tap.dominantFrequency(between: 200, and: 900)
let e440 = tap.energyDB(between: 400, and: 480)
let e3k  = tap.energyDB(between: 2800, and: 3200)
let eQuiet = tap.energyDB(between: 8000, and: 12000)
check("fondamentale trouvée à 440 Hz", abs(f0 - 440) < 6, String(format: "%.1f Hz", f0))
check("la bande 440 Hz domine", e440 - eQuiet > 40, String(format: "%+.1f dB au-dessus du silence", e440 - eQuiet))
check("la composante 3 kHz est bien plus faible", e440 - e3k > 8, String(format: "écart %+.1f dB", e440 - e3k))
print(String(format: "  repères : 440 Hz %+.1f dB · 3 kHz %+.1f dB · 10 kHz %+.1f dB", e440, e3k, eQuiet))

print("\n\(fails == 0 ? "TOUS LES FORMATS SONT VALIDES" : "\(fails) PROBLÈME(S)")")
print("Fichiers : \(outDir.path)")
exit(fails == 0 ? 0 : 1)
