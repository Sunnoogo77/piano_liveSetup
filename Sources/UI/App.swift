import SwiftUI
import AppKit

let configURL = URL(fileURLWithPath:
    AppPaths.configFile.path)

func loadConfig() -> RigConfig {
    if let d = try? Data(contentsOf: configURL),
       let c = try? JSONDecoder().decode(RigConfig.self, from: d), !c.presets.isEmpty { return c }
    return RigConfig.defaults()
}

enum Tab: String, CaseIterable, Identifiable {
    case play = "Jeu", eq = "Égaliseur", chords = "Accords"
    case keys = "Clavier", record = "Enregistrer", devices = "Périphériques"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .play:    return "play.circle.fill"
        case .eq:      return "waveform.badge.magnifyingglass"
        case .chords:  return "music.quarternote.3"
        case .keys:    return "pianokeys.inverse"
        case .record:  return "record.circle"
        case .devices: return "cable.connector"
        }
    }
}

// MARK: - Modèle

@MainActor
final class RigModel: ObservableObject {
    let engine: LiveEngine

    @Published var ready = false
    @Published var loadingLabel = "Préparation…"
    @Published var loadingProgress = 0.0
    @Published var fatalError: String?

    @Published var presetIndex = 0
    @Published var transpose: Int32 = 0
    @Published var octave: Int32 = 0
    @Published var master: Float = 0.85
    @Published var layerMix: Float = 1
    @Published var bands: [EQBand] = defaultEQ()
    @Published var selectedBand = 2
    @Published var drive: Float = 0
    @Published var tremRate: Float = 0
    @Published var tremDepth: Float = 0
    @Published var comp: Float = 0
    @Published var localSilenced = true
    @Published var hasKeyboard = false
    @Published var deviceNote: String?
    @Published var followOutput = true
    @Published var search = ""
    @Published var categoryFilter: Category? = nil

    @Published var tab: Tab = .play

    // Accords et notes tenues
    @Published var chord: ChordResult = .empty
    @Published var sounding: [Int] = []
    @Published var chordHistory: [ChordResult] = []

    // Enregistrement
    @Published var isRecording = false
    @Published var recSeconds: Double = 0
    @Published var recNotes = 0
    @Published var recordAudio = true
    @Published var takeName = ""
    @Published var tempo: Double = 100
    @Published var takes: [TakeMeta] = []
    @Published var lastTake: TakeMeta?

    // Périphériques
    @Published var audioDevices: [String] = []
    @Published var micDevices: [(id: UInt32, name: String)] = []
    @Published var micDeviceID: UInt32 = 0
    @Published var micOn = false
    @Published var micMonitoring = false
    @Published var micGain: Float = 0.8
    @Published var micComp: Float = 0.35
    @Published var micBands: [EQBand] = micDefaultEQ()
    @Published var micSelectedBand = 2
    @Published var micPeakDB: Float = -60
    @Published var micMessage: String?

    @Published var peakDBL: Float = -60
    @Published var peakDBR: Float = -60
    @Published var holdL: Float = -60
    @Published var holdR: Float = -60
    @Published var held = 0
    @Published var midiLive = false

    var presets: [Preset] { engine.config.presets }
    var preset: Preset { engine.config.presets[min(presetIndex, presets.count - 1)] }

    var filtered: [(offset: Int, element: Preset)] {
        presets.enumerated().filter { _, p in
            (categoryFilter == nil || p.category == categoryFilter!) &&
            (search.isEmpty || p.name.localizedCaseInsensitiveContains(search)
                            || p.subtitle.localizedCaseInsensitiveContains(search)
                            || p.category.rawValue.localizedCaseInsensitiveContains(search))
        }.map { (offset: $0.offset, element: $0.element) }
    }

    init() {
        engine = LiveEngine(config: loadConfig())
        master = engine.config.masterVolume
    }

    func boot() {
        AppPaths.ensure()
        Task.detached(priority: .userInitiated) { [engine] in
            do {
                try engine.loadBanks { file, i, total in
                    Task { @MainActor [weak self] in
                        self?.loadingProgress = Double(i) / Double(max(total, 1))
                        self?.loadingLabel = file.isEmpty ? "Démarrage du moteur…"
                            : "Chargement · \(file.replacingOccurrences(of: ".sf2", with: "").replacingOccurrences(of: ".sf3", with: ""))"
                    }
                }
                try engine.startAudio()
                // startMIDI doit être sur le thread principal : voir son commentaire.
                await MainActor.run { [weak self] in
                    engine.startMIDI()
                    self?.finishBoot()
                }
            } catch {
                await MainActor.run { [weak self] in self?.fatalError = error.localizedDescription }
            }
        }
    }

    private func finishBoot() {
        let startIndex = presets.firstIndex { $0.name == engine.config.currentPreset } ?? 0
        engine.selectPreset(startIndex)
        engine.resetTranspose()
        engine.setMasterVolume(master)
        if engine.canControlPianoLocal { engine.setPianoLocalControl(false) }
        localSilenced = engine.config.localControlOff
        hasKeyboard = engine.hasKeyboard
        followOutput = engine.followKeyboardOutput
        syncFromEngine(startIndex)
        refreshTakes()
        refreshDevices()
        engine.onSetupChanged = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hasKeyboard = self.engine.hasKeyboard
                self.localSilenced = self.engine.config.localControlOff
                self.refreshDevices()
                if let note = self.engine.lastSwitchNote {
                    self.deviceNote = note
                    self.engineClearSwitchNote()
                }
                self.objectWillChange.send()
            }
        }
        ready = true
        Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        func dB(_ v: Float) -> Float { v > 0 ? 20 * log10(v) : -60 }
        let l = dB(engine.peakL), r = dB(engine.peakR)
        peakDBL = max(l, peakDBL - 1.8)
        peakDBR = max(r, peakDBR - 1.8)
        holdL = max(l, holdL - 0.35)
        holdR = max(r, holdR - 0.35)
        held = engine.heldNotes
        midiLive = engine.secondsSinceLastNote < 0.5
        if hasKeyboard != engine.hasKeyboard { hasKeyboard = engine.hasKeyboard }

        let notes = engine.soundingNotes
        if notes != sounding {
            sounding = notes
            let c = ChordDetector.detect(notes)
            if c.symbol != chord.symbol {
                if notes.count >= 3, c.symbol != "—", c.symbol != "?" {
                    chordHistory.insert(c, at: 0)
                    if chordHistory.count > 24 { chordHistory.removeLast() }
                }
                chord = c
            } else {
                chord = c
            }
        }

        if isRecording {
            recSeconds = engine.recordedSeconds
            recNotes = engine.recordedNoteCount
        }
        if micOn { micPeakDB = engine.mic.inputPeak > 0 ? 20 * log10(engine.mic.inputPeak) : -60 }
    }

    // MARK: Enregistrement

    func toggleRecording() {
        if isRecording {
            let name = takeName.isEmpty ? defaultTakeName() : takeName
            lastTake = engine.stopTake(name: name, tempo: tempo)
            isRecording = false
            recSeconds = 0; recNotes = 0
            takeName = ""
            refreshTakes()
        } else {
            _ = engine.startTake(withAudio: recordAudio)
            isRecording = true
        }
    }

    private func defaultTakeName() -> String {
        let f = DateFormatter(); f.dateFormat = "d MMMM 'à' HH'h'mm"
        f.locale = Locale(identifier: "fr_FR")
        return "\(preset.name) — \(f.string(from: Date()))"
    }

    func refreshTakes() { takes = TakeStore.list() }

    func deleteTake(_ id: String) {
        TakeStore.delete(id)
        if lastTake?.id == id { lastTake = nil }
        refreshTakes()
    }

    func revealTake(_ id: String) {
        NSWorkspace.shared.activateFileViewerSelecting([TakeStore.folder(id)])
    }

    func openFile(_ url: URL) { NSWorkspace.shared.open(url) }

    // MARK: Périphériques

    func engineClearSwitchNote() { engine.clearSwitchNote() }

    func setFollowOutput(_ on: Bool) {
        followOutput = on
        engine.followKeyboardOutput = on
        if on { engine.followKeyboardIfPossible() }
    }

    func refreshDevices() {
        audioDevices = CA.outputDevices().map { $0.1 }
        micDevices = MicInput.inputDevices().map { (id: UInt32($0.0), name: $0.1) }
        if micDeviceID == 0, let first = micDevices.first { micDeviceID = first.id }
    }

    func chooseAudioDevice(_ name: String) {
        if engine.switchAudioDevice(named: name) {
            micMessage = nil
            objectWillChange.send()
        } else {
            micMessage = "Impossible de basculer sur « \(name) »."
        }
    }

    func toggleMic() {
        if micOn {
            engine.stopMic(); micOn = false; micMonitoring = false
            engine.mic.monitoring = false
            micPeakDB = -60
        } else {
            guard micDeviceID != 0 else { micMessage = "Aucune entrée disponible."; return }
            if engine.startMic(deviceID: micDeviceID) {
                micOn = true
                engine.mic.gain = micGain
                engine.mic.chain.compAmount = micComp
                engine.mic.chain.updateEQ(micBands)
                engine.mic.monitoring = micMonitoring
                micMessage = nil
            } else {
                micMessage = engine.mic.lastError ?? "Entrée refusée."
            }
        }
    }

    func setMicGain(_ v: Float) { micGain = v; engine.mic.gain = v }
    func setMicComp(_ v: Float) { micComp = v; engine.mic.chain.compAmount = v }
    func setMicMonitoring(_ on: Bool) { micMonitoring = on; engine.mic.monitoring = on }
    func commitMicBands() { engine.mic.chain.updateEQ(micBands) }
    func resetMicEQ() { micBands = micDefaultEQ(); commitMicBands() }

    private func syncFromEngine(_ i: Int) {
        presetIndex = i
        let p = engine.config.presets[i]
        bands = p.eqBands
        layerMix = engine.currentLayerMix
        drive = p.drive
        tremRate = p.tremRate
        tremDepth = p.tremDepth
        comp = p.compAmount
        transpose = engine.transpose
        octave = engine.octave
    }

    func select(_ i: Int) {
        guard presets.indices.contains(i) else { return }
        engine.selectPreset(i)
        engine.rememberCurrent(presets[i].name)
        syncFromEngine(i)
    }
    func step(_ d: Int) { select(max(0, min(presets.count - 1, presetIndex + d))) }

    func nudgeTranspose(_ d: Int32) { engine.nudgeTranspose(d); transpose = engine.transpose }
    func nudgeOctave(_ d: Int32) { engine.nudgeOctave(d); octave = engine.octave }
    func resetPitch() { engine.resetTranspose(); transpose = 0; octave = 0 }

    func setMaster(_ v: Float) { master = v; engine.setMasterVolume(v) }
    func setLayer(_ v: Float) { layerMix = v; engine.setLayerMix(v) }
    func commitBand(_ i: Int) { engine.updateEQBand(i, freq: bands[i].freq, gain: bands[i].gain,
                                                    q: bands[i].q, enabled: bands[i].enabled) }
    func commitBands() { for i in bands.indices { commitBand(i) } }
    func resetEQ() { engine.resetEQ(); bands = engine.preset.eqBands }
    func setDrive(_ v: Float) { drive = v; engine.setDrive(v) }
    func setTrem(rate: Float, depth: Float) { tremRate = rate; tremDepth = depth; engine.setTremolo(rate: rate, depth: depth) }
    func setComp(_ v: Float) { comp = v; engine.setComp(v) }
    func panic() { engine.panic(); held = 0 }

    func toggleLocal() {
        localSilenced.toggle()
        engine.setPianoLocalControl(!localSilenced)
    }

    func save() {
        var cfg = engine.config
        cfg.masterVolume = master
        cfg.currentPreset = preset.name
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(cfg).write(to: configURL)
    }
    func shutdown() { save(); engine.shutdown() }
}

// MARK: - Écran de chargement

struct BootView: View {
    @ObservedObject var m: RigModel
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "pianokeys")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Tone.accent)
            VStack(spacing: 6) {
                Text("Piano Live Setup")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tone.txt0)
                Text("YDP-145 · scène")
                    .font(.system(size: 11)).tracking(2)
                    .foregroundStyle(Tone.txt2)
            }
            if let e = m.fatalError {
                Text(e).font(.system(size: 12)).foregroundStyle(Tone.hot)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            } else {
                VStack(spacing: 9) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tone.bg2)
                            Capsule().fill(Tone.accent)
                                .frame(width: g.size.width * m.loadingProgress)
                                .animation(.easeOut(duration: 0.25), value: m.loadingProgress)
                        }
                    }
                    .frame(width: 280, height: 4)
                    Text(m.loadingLabel)
                        .font(.system(size: 10.5)).foregroundStyle(Tone.txt2)
                        .frame(height: 14)
                }
            }
            Spacer()
            Text("1,5 Go d'échantillons · chargement unique au lancement")
                .font(.system(size: 9.5)).foregroundStyle(Tone.txt2.opacity(0.7))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tone.bg0)
    }
}
