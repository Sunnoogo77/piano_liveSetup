import Foundation

// Étalonnage hors ligne. Chaque preset est rendu avec sa chaîne complète
// (couches, EQ, drive, trémolo, compresseur), puis mesuré. Les gains sont
// calculés pour une sonie égale, sous un plafond de crête garanti.

let soundsDir = AppPaths.sounds.path
let configPath = AppPaths.configFile.path
let sampleRate: Double = 44100
let chord: [Int32] = [40, 48, 52, 55, 60, 64]   // couvre aussi la zone grave des partages
let velocity: Int32 = 96
let holdSeconds = 2.5
let tailSeconds = 2.0
let headroomDB: Float = 6.0

AppPaths.ensure()
guard let settings = new_fluid_settings() else { exit(1) }
fluid_settings_setnum(settings, "synth.gain", 1.0)
fluid_settings_setint(settings, "synth.polyphony", 512)
fluid_settings_setint(settings, "synth.reverb.active", 1)
fluid_settings_setint(settings, "synth.chorus.active", 1)
fluid_settings_setnum(settings, "synth.reverb.damp", 0.3)
fluid_settings_setnum(settings, "synth.reverb.level", 0.7)
fluid_settings_setnum(settings, "synth.reverb.room-size", 0.5)
fluid_settings_setnum(settings, "synth.reverb.width", 0.8)
fluid_settings_setnum(settings, "synth.chorus.depth", 3.6)
fluid_settings_setnum(settings, "synth.chorus.level", 0.55)
fluid_settings_setint(settings, "synth.chorus.nr", 4)
fluid_settings_setnum(settings, "synth.chorus.speed", 0.36)
fluid_settings_setnum(settings, "synth.sample-rate", sampleRate)
guard let synth = new_fluid_synth(settings) else { exit(1) }

print("Chargement des banques…")
var sfIDs: [String: Int32] = [:]
for file in Bank.all {
    let path = soundsDir + "/" + file
    guard FileManager.default.fileExists(atPath: path) else { print("  absente : \(file)"); continue }
    let id = fluid_synth_sfload(synth, path, 0)
    if id == FLUID_FAILED { print("  illisible : \(file)") } else { sfIDs[file] = id }
}
print("  \(sfIDs.count) banques chargées")
let missing = Bank.all.filter { sfIDs[$0] == nil }
if !missing.isEmpty {
    let r = BankResolver(sfIDs: sfIDs)
    print("  \(missing.count) absente(s), remplacée(s) :")
    for m in missing {
        let sub = r.resolve(BankRef(file: m, sfBank: 0, program: 0))?.file ?? "aucun équivalent"
        print("    \(m) → \(sub)")
    }
}
print("")

var config: RigConfig
if let d = FileManager.default.contents(atPath: configPath),
   let c = try? JSONDecoder().decode(RigConfig.self, from: d), !c.presets.isEmpty {
    config = c
    print("Configuration existante rechargée (réglages conservés).\n")
} else {
    config = RigConfig.defaults()
    print("Bibliothèque reconstruite depuis les valeurs par défaut.\n")
}

struct Measure { var peak: Float; var rms: Float }

func render(_ p: Preset) -> Measure? {
    let chain = ProcessorChain()
    chain.sampleRate = Float(sampleRate)
    chain.updateEQ(p.eqBands)
    chain.drive = p.drive
    chain.tremRate = p.tremRate
    chain.tremDepth = p.tremDepth
    chain.compAmount = p.compAmount
    chain.gain = 1
    chain.limiterEnabled = false        // on veut les vraies crêtes

    var any = false
    let resolver = BankResolver(sfIDs: sfIDs)
    for ch in Int32(0)..<3 { fluid_synth_all_sounds_off(synth, ch); fluid_synth_cc(synth, ch, 7, 0) }
    for (i, layer) in p.layers.prefix(3).enumerated() {
        guard let r = resolver.resolve(layer.bank) else { continue }
        let ch = Int32(i)
        fluid_synth_program_select(synth, ch, r.id, r.bank, r.program)
        let vol = i == 0 ? layer.volume : p.layerMix
        fluid_synth_cc(synth, ch, 7, Int32(max(0, min(127, vol * 127))))
        fluid_synth_cc(synth, ch, 10, Int32(max(0, min(127, (layer.pan + 1) * 63.5))))
        fluid_synth_cc(synth, ch, 91, layer.reverb)
        fluid_synth_cc(synth, ch, 93, layer.chorus)
        any = true
    }
    guard any else { return nil }

    let block = 512
    var l = [Float](repeating: 0, count: block)
    var r = [Float](repeating: 0, count: block)
    var peak: Float = 0, sumSq: Double = 0
    var n = 0
    var elapsed = 0.0
    // La sonie perçue au jeu se juge sur l'attaque, pas sur la queue de réverbération :
    // sans cette fenêtre, un orgue tenu écraserait un piano qui décroît.
    let loudnessFrom = 0.05, loudnessTo = 1.2

    func pump(_ seconds: Double) {
        for _ in 0..<(Int(seconds * sampleRate) / block) {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    fluid_synth_write_float(synth, Int32(block), lp.baseAddress!, 0, 1, rp.baseAddress!, 0, 1)
                    chain.process(lp.baseAddress!, rp.baseAddress!, frames: block)
                }
            }
            let inWindow = elapsed >= loudnessFrom && elapsed < loudnessTo
            for i in 0..<block {
                peak = max(peak, max(abs(l[i]), abs(r[i])))
                if inWindow {
                    sumSq += Double(l[i] * l[i] + r[i] * r[i])
                    n += 2
                }
            }
            elapsed += Double(block) / sampleRate
        }
    }

    let gamma = p.velocityGamma
    let vOut = Int32(max(1, min(127, Int(127 * pow(Float(velocity) / 127, gamma)))))
    for note in chord {
        for (i, layer) in p.layers.prefix(3).enumerated() {
            guard note >= Int32(layer.loKey), note <= Int32(layer.hiKey) else { continue }
            fluid_synth_noteon(synth, Int32(i), note + layer.semitones, vOut)
        }
    }
    pump(holdSeconds)
    for note in chord {
        for (i, layer) in p.layers.prefix(3).enumerated() {
            guard note >= Int32(layer.loKey), note <= Int32(layer.hiKey) else { continue }
            fluid_synth_noteoff(synth, Int32(i), note + layer.semitones)
        }
    }
    pump(tailSeconds)
    return Measure(peak: peak, rms: Float(sqrt(sumSq / Double(max(1, n)))))
}

func db(_ v: Float) -> String { v <= 0 ? "  -inf" : String(format: "%+6.1f", 20 * log10(v)) }

print("Mesure de \(config.presets.count) presets…\n")
var measures: [Measure?] = []
var failures: [String] = []
for p in config.presets {
    guard let m = render(p), m.rms > 0.00005 else {
        print(String(format: "  ÉCHEC  %-20s (banque manquante ou rendu muet)", (p.name as NSString).utf8String!))
        failures.append(p.name); measures.append(nil); continue
    }
    measures.append(m)
    print(String(format: "  %-20s crête %@ dB   RMS %@ dB", (p.name as NSString).utf8String!, db(m.peak), db(m.rms)))
}

let ceiling: Float = pow(10, -headroomDB / 20)
let valid = measures.compactMap { $0 }
guard !valid.isEmpty else { print("\nAucun preset mesurable."); exit(1) }

// Sonie commune. Pour chaque son, la sonie qu'il pourrait atteindre sans que
// sa crête dépasse le plafond ; la cible est prise parmi les plus basses,
// mais pas la plus basse.
//
// Prendre le minimum revient à laisser un seul son décider du niveau de toute
// la bibliothèque : une kalimba, un pizzicato — une attaque sèche suivie de
// presque rien — ont une crête haute et une sonie très basse, et elles
// tiraient tout le reste douze décibels plus bas. Le huitième le plus bas
// redonne la cible qu'on avait avant l'arrivée de ces familles.
let reachable = valid.map { $0.rms * (ceiling / $0.peak) }.sorted()
let targetRMS = reachable[reachable.count / 8]

print(String(format: "\nSonie cible : %@ dB RMS, plafond de crête %@ dB\n", db(targetRMS), db(ceiling)))
var worstPeak: Float = 0
var limited: [(String, Float)] = []
for i in config.presets.indices {
    guard let m = measures[i] else { config.presets[i].gain = 1; continue }
    // Le plafond de crête l'emporte sur la sonie commune : un son qui ne peut
    // pas l'atteindre sans écrêter reste en dessous, et on le dit.
    let wanted = targetRMS / m.rms
    let allowed = ceiling / m.peak
    let g = min(wanted, allowed)
    if allowed < wanted * 0.9 {
        limited.append((config.presets[i].name, 20 * log10(allowed / wanted)))
    }
    config.presets[i].gain = g
    worstPeak = max(worstPeak, m.peak * g)
}
print(String(format: "Pire crête après étalonnage : %@ dB", db(worstPeak)))
if limited.isEmpty {
    print("Tous les sons atteignent la sonie commune.")
} else {
    print("Bridés par leur crête, sous la sonie commune :")
    for (name, d) in limited.sorted(by: { $0.1 < $1.1 }) {
        print(String(format: "  %-20s %+.1f dB", (name as NSString).utf8String!, d))
    }
}
print("Presets en échec : \(failures.isEmpty ? "aucun" : failures.joined(separator: ", "))")

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try! FileManager.default.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
try! enc.encode(config).write(to: URL(fileURLWithPath: configPath))
print("\nÉcrit : \(configPath)")
exit(failures.isEmpty ? 0 : 2)
