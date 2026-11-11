import SwiftUI
import AppKit

/// Trace de démarrage, sur la sortie d'erreur. Invisible quand on double-clique
/// sur l'application ; précieuse quand on la lance depuis le Terminal pour
/// comprendre pourquoi elle reste sur son écran de chargement :
///
///     "/Applications/Piano Live Setup.app/Contents/MacOS/PianoLiveSetup"
func trace(_ text: String) {
    FileHandle.standardError.write(Data(("[piano] " + text + "\n").utf8))
}

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
    /// Message affiché quand l'ouverture de la sortie audio ne répond plus.
    @Published var bootHint: String?

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
    @Published var usbUnreadable: [USBDevice] = []
    @Published var micMessage: String?
    @Published var micAuth = MicPermission.status
    /// Le périphérique est ouvert mais n'envoie que des zéros.
    @Published var micSilent = false
    private var micSilentSince: Date?

    // Contrôle à distance
    let remote = RemoteServer()
    @Published var remoteOn = false
    @Published var remoteAddresses: [String] = []
    @Published var remoteKey = ""
    @Published var remoteMessage: String?
    @Published var remoteClients = 0

    // Mises à jour
    @Published var updateLatest: String?
    @Published var updateNewer = false
    @Published var updateChecking = false
    @Published var updateMessage: String?

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
        // CoreMIDI d'abord, avant que quoi que ce soit d'autre n'y touche :
        // le premier client du processus décide où les notifications sont
        // livrées. Voir createMIDIClient().
        engine.startMIDI()
        trace("démarrage — MIDI en place\(engine.midiClientError.map { " : " + $0 } ?? "")")
        Task.detached(priority: .userInitiated) { [engine] in
            do {
                trace("chargement des banques…")
                try engine.loadBanks { file, i, total in
                    Task { @MainActor [weak self] in
                        self?.loadingProgress = Double(i) / Double(max(total, 1))
                        self?.loadingLabel = file.isEmpty ? "Démarrage du moteur…"
                            : "Chargement · \(file.replacingOccurrences(of: ".sf2", with: "").replacingOccurrences(of: ".sf3", with: ""))"
                    }
                }
                trace("banques chargées — ouverture de l'audio")
                await MainActor.run { [weak self] in self?.armAudioWatchdog() }
                try engine.startAudio()
                trace("audio ouvert : \(engine.statusAudio)")
                await MainActor.run { [weak self] in
                    // L'audio est ouvert : on peut enfin suivre le clavier.
                    engine.followKeyboardIfPossible()
                    trace("MIDI prêt : \(engine.midiSourceNames.joined(separator: ", "))")
                    self?.bootHint = nil
                    self?.finishBoot()
                    trace("démarrage terminé")
                }
            } catch {
                trace("ÉCHEC : \(error.localizedDescription)")
                await MainActor.run { [weak self] in self?.fatalError = error.localizedDescription }
            }
        }
    }

    /// CoreAudio peut rester bloqué indéfiniment sur `setDeviceID` quand le
    /// périphérique visé ne répond plus — un piano USB dont la carte son s'est
    /// vexée, par exemple. L'appel n'est pas annulable : on ne peut pas le
    /// rattraper, mais on peut au moins cesser de laisser l'utilisateur devant
    /// un écran de chargement muet.
    private func armAudioWatchdog() {
        let target = engine.config.audioDeviceName
        let named = target.isEmpty ? "la sortie choisie" : "« \(target) »"
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self, !self.ready, self.fatalError == nil else { return }
            self.bootHint = "\(named) ne répond pas. Éteignez puis rallumez "
                + "l'instrument, ou débranchez et rebranchez son câble USB : "
                + "le démarrage reprendra tout seul."
            trace("la sortie audio ne répond pas depuis 9 s")
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
        syncMicChain()
        refreshTakes()
        refreshDevices()
        remote.onCommand = { [weak self] action, args in
            MainActor.assumeIsolated { self?.handleRemote(action, args) }
        }
        if engine.config.remoteEnabled { toggleRemote() }
        if engine.config.checkUpdates {
            // Quelques secondes après le démarrage : on ne retarde pas le son
            // pour une question de version.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.checkForUpdate()
            }
        }
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
        if micOn { watchMic() }
        if remoteOn { publishRemote() }
    }

    /// Un périphérique peut s'ouvrir sans rien envoyer : autorisation refusée,
    /// mauvaise entrée, iPhone verrouillé. Plutôt que de laisser croire que
    /// tout va bien, on le dit au bout de deux secondes et demie.
    private func watchMic() {
        let peak = engine.mic.inputPeak
        micPeakDB = peak > 0 ? 20 * log10(peak) : -60
        if peak > 0.00005 {
            micSilentSince = nil
            if micSilent { micSilent = false; micMessage = nil; refreshRemoteSlow(force: true) }
            return
        }
        guard !micSilent, let since = micSilentSince,
              Date().timeIntervalSince(since) > 2.5 else { return }
        micSilent = true
        let who = engine.mic.deviceName
        micMessage = micAuth == .authorized
            ? "« \(who) » est ouvert mais n'envoie rien. Vérifiez que c'est la bonne "
              + "entrée et qu'elle n'est pas coupée — pour un iPhone, qu'il est "
              + "déverrouillé, à proximité, et qu'il ne sert pas déjà ailleurs."
            : "« \(who) » n'envoie rien : micro \(micAuth.human). \(MicPermission.settingsHint)"
        refreshRemoteSlow(force: true)
    }

    // MARK: Contrôle à distance

    func toggleRemote() {
        if remoteOn {
            remote.stop(); remoteOn = false; remoteAddresses = []; remoteKey = ""
            remoteMessage = nil
            engine.setRemoteEnabled(false)
            save()
        } else {
            guard remote.start(port: UInt16(engine.config.remotePort),
                               key: engine.config.remoteKey) else {
                remoteMessage = remote.lastError ?? "démarrage impossible"
                return
            }
            remoteOn = true
            remoteKey = remote.token
            remoteAddresses = remote.addresses
            remoteMessage = remote.addresses.isEmpty
                ? "Aucune adresse réseau : le Mac est-il connecté au Wi-Fi ?" : nil
            engine.setRemoteEnabled(true)
            engine.setRemoteKey(remote.token)
            save()                       // la clé survit même à un arrêt brutal
            publishRemoteLibrary()
            refreshRemoteSlow(force: true)
            publishRemote()
        }
    }

    private func publishRemoteLibrary() {
        let list = presets.map { ["name": $0.name, "subtitle": $0.subtitle,
                                  "category": $0.category.rawValue] }
        if let d = try? JSONSerialization.data(withJSONObject: list) { remote.publish(library: d) }
    }

    // L'état part en deux morceaux. Ce qui bouge à chaque image passe par le
    // flux ; ce qui change rarement n'est republié que lorsqu'il a vraiment
    // changé, et la page le relit alors d'elle-même grâce au numéro de
    // révision. C'est ce qui permet d'avoir un spectre fluide sans inonder
    // le réseau de listes de sons.

    private var remoteRev = 0
    private var remoteSlowBody = Data()
    private var remoteTicks = 0

    private func publishRemote() {
        remoteTicks += 1
        if remoteTicks % 8 == 0 { refreshRemoteSlow() }

        // L'analyseur n'est calculé que par celui qui le regarde : c'est la
        // vue de l'écran Égaliseur qui appelle `analyse()`. Quand cet écran
        // n'est pas affiché sur le Mac, personne ne le fait — et la tablette
        // recevrait un spectre plat. On le réveille donc ici, mais seulement
        // s'il y a quelqu'un au bout du fil.
        if tab != .eq, remote.streamCount > 0 || remote.clientCount > 0 {
            engine.spectrum.analyse()
        }

        var live: [String: Any] = [
            "rev": remoteRev,
            "presetIndex": presetIndex,
            "transpose": Int(transpose), "octave": Int(octave),
            "master": master, "layerMix": layerMix,
            "peakL": peakDBL, "peakR": peakDBR, "holdL": holdL, "holdR": holdR,
            "chord": chord.symbol, "chordQuality": chord.quality,
            "chordNotes": chord.noteNames.joined(separator: " "),
            "chordDegrees": chord.degrees.joined(separator: " · "),
            "sounding": sounding, "held": held, "midiLive": midiLive,
            "hasKeyboard": hasKeyboard,
            "recording": isRecording, "recSeconds": Int(recSeconds), "recNotes": recNotes,
            "micPeak": micOn ? micPeakDB : -120,
            "history": chordHistory.prefix(14).map { $0.symbol },
            "spectrum": spectrumPayload(engine.spectrum),
        ]
        // Le spectre du micro ne part que quand l'entrée est ouverte : sinon
        // c'est 172 caractères de silence, trente fois par seconde.
        if micOn { live["micSpectrum"] = spectrumPayload(engine.mic.spectrum) }
        if let d = try? JSONSerialization.data(withJSONObject: live) { remote.publish(live: d) }
        let n = remote.streamCount
        if n != remoteClients { remoteClients = n }
    }

    /// Les 128 bandes de l'analyseur, un octet par bande : −72 dB → 0,
    /// 0 dB → 255. 128 octets, soit 172 caractères, par image.
    private func spectrumPayload(_ tap: SpectrumTap) -> String {
        let bands = tap.bandsDB
        var bytes = [UInt8](repeating: 0, count: bands.count)
        for i in bands.indices {
            let v = (max(-72, min(0, bands[i])) + 72) / 72 * 255
            bytes[i] = UInt8(max(0, min(255, v.rounded())))
        }
        return Data(bytes).base64EncodedString()
    }

    private func refreshRemoteSlow(force: Bool = false) {
        guard remoteOn else { return }
        let p = preset
        // 0 : ce son n'est pas partagé. La page n'assombrit alors rien du tout.
        let splitPoint = (p.category == .split && p.layers.count > 1) ? Int(p.layers[1].loKey) : 0
        let eqList: [[String: Any]] = bands.map {
            ["label": $0.label, "kind": $0.kind.tag, "freq": $0.freq,
             "gain": $0.gain, "q": $0.q, "enabled": $0.enabled,
             "usesGain": $0.kind.usesGain]
        }
        let takeList: [[String: Any]] = takes.prefix(12).map {
            ["id": $0.id, "name": $0.name, "seconds": Int($0.duration),
             "notes": $0.noteCount, "audio": $0.hasAudio,
             "preset": $0.preset, "tempo": Int($0.tempo),
             "when": Self.remoteDateFormatter.string(from: $0.date)]
        }
        var slow: [String: Any] = [
            "preset": p.name, "subtitle": p.subtitle, "category": p.category.rawValue,
            "presetIndex": presetIndex, "hasLayer": p.hasSecondLayer, "split": splitPoint,
            "eq": eqList,
            "fx": ["drive": drive, "tremRate": tremRate, "tremDepth": tremDepth, "comp": comp],
            "takes": takeList, "recordAudio": recordAudio, "tempo": Int(tempo),
            "keyboards": engine.midiSourceNames,
            "midiEvents": engine.midiNotifications,
            "midiError": engine.midiClientError ?? "",
            "output": engine.audioDeviceLabel, "audioStatus": engine.statusAudio,
            "version": AppInfo.version, "commit": AppInfo.commit, "repo": AppInfo.repoURL,
            "micOn": micOn,
            "mic": [
                "on": micOn, "auth": micAuth.rawValue, "authText": micAuth.human,
                "device": engine.mic.deviceName, "deviceID": Int(micDeviceID),
                "devices": micDevices.map { ["id": Int($0.id), "name": $0.name] },
                "gain": micGain, "comp": micComp,
                "monitoring": micMonitoring, "silent": micSilent,
                "message": micMessage ?? "",
                "bands": micBands.map {
                    ["label": $0.label, "kind": $0.kind.tag, "freq": $0.freq,
                     "gain": $0.gain, "q": $0.q, "enabled": $0.enabled,
                     "usesGain": $0.kind.usesGain]
                },
            ],
        ]
        if let latest = updateLatest {
            slow["update"] = ["latest": latest, "newer": updateNewer]
        }
        if let msg = updateMessage { slow["updateMessage"] = msg }

        guard let body = try? JSONSerialization.data(withJSONObject: slow,
                                                     options: [.sortedKeys]) else { return }
        guard force || body != remoteSlowBody else { return }
        remoteSlowBody = body
        remoteRev += 1
        slow["rev"] = remoteRev
        if let d = try? JSONSerialization.data(withJSONObject: slow) { remote.publish(state: d) }
    }

    private static let remoteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM, HH'h'mm"
        return f
    }()

    private func handleRemote(_ action: String, _ args: [String: Any]) {
        func number(_ key: String) -> Float? {
            if let d = args[key] as? Double { return Float(d) }
            if let i = args[key] as? Int { return Float(i) }
            return nil
        }
        switch action {
        case "preset":
            if let i = args["index"] as? Int { select(i) }
        case "transpose":
            if let set = args["set"] as? Int, set == 0 { resetPitch() }
            else if let d = args["delta"] as? Int { nudgeTranspose(Int32(d)) }
        case "octave":
            if let d = args["delta"] as? Int { nudgeOctave(Int32(d)) }
        case "master":
            if let v = number("value") { setMaster(v) }
        case "layer":
            if let v = number("value") { setLayer(v) }
        case "panic": panic()
        case "record": toggleRecording()
        case "recordAudio":
            if let on = args["on"] as? Bool { recordAudio = on }
        case "tempo":
            if let v = number("value") { tempo = Double(min(240, max(30, v))) }
        case "eqband":
            if let i = args["index"] as? Int, let g = number("gain"), bands.indices.contains(i) {
                bands[i].gain = min(18, max(-18, g)); commitBand(i)
            }
        case "eqfreq":
            if let i = args["index"] as? Int, let f = number("freq"), bands.indices.contains(i) {
                bands[i].freq = min(20000, max(20, f)); commitBand(i)
            }
        case "eqq":
            if let i = args["index"] as? Int, let q = number("q"), bands.indices.contains(i) {
                bands[i].q = min(12, max(0.2, q)); commitBand(i)
            }
        case "eqenabled":
            if let i = args["index"] as? Int, let on = args["on"] as? Bool,
               bands.indices.contains(i) {
                bands[i].enabled = on; commitBand(i)
            }
        case "eqreset": resetEQ()
        case "fx":
            if let v = number("drive") { setDrive(v) }
            if let v = number("comp") { setComp(v) }
            if let v = number("tremDepth") { setTrem(rate: tremRate > 0.1 ? tremRate : 5.2, depth: v) }
            if let v = number("tremRate") { setTrem(rate: v, depth: tremDepth) }
        case "mic": toggleMic()
        case "micGain":
            if let v = number("value") { setMicGain(min(2, max(0, v))) }
        case "micComp":
            if let v = number("value") { setMicComp(min(1, max(0, v))) }
        case "micMonitor":
            if let on = args["on"] as? Bool {
                setMicMonitoring(on)
                if on, micOn, micMessage?.hasPrefix("Micro ouvert") == true { micMessage = nil }
            }
        case "micDevice":
            if let id = args["id"] as? Int { chooseMicDevice(UInt32(id)) }
        case "micBand":
            if let i = args["index"] as? Int, let g = number("gain"),
               micBands.indices.contains(i) {
                micBands[i].gain = min(18, max(-18, g)); commitMicBands()
            }
        case "micFreq":
            if let i = args["index"] as? Int, let f = number("freq"),
               micBands.indices.contains(i) {
                micBands[i].freq = min(20000, max(20, f)); commitMicBands()
            }
        case "micReset": resetMicEQ()
        case "micRescan": refreshDevices()
        case "checkUpdate": checkForUpdate(manual: true)
        case "selectKeyboard": engine.rescanMIDI()
        default: break
        }
        refreshRemoteSlow(force: true)
        publishRemote()
    }

    // MARK: Mises à jour

    /// Demande à GitHub le numéro de la dernière version publiée. Rien n'est
    /// téléchargé ni installé : c'est à vous de lancer la mise à jour.
    func checkForUpdate(manual: Bool = false) {
        guard !updateChecking else { return }
        updateChecking = true
        if manual { updateMessage = "Vérification…" }
        UpdateCheck.run { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.updateChecking = false
                switch result {
                case .success(let o):
                    self.updateLatest = o.latest
                    self.updateNewer = o.isNewer
                    self.updateMessage = o.isNewer
                        ? "La version \(o.latest) est disponible."
                        : (manual ? "Vous avez la dernière version." : nil)
                case .failure(let e):
                    self.updateNewer = false
                    self.updateMessage = manual ? e.description : nil
                }
                self.refreshRemoteSlow(force: true)
            }
        }
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

    /// Ouvre directement le volet Microphone des réglages de confidentialité.
    func openMicSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(u)
        }
    }

    func refreshMicAuth() { micAuth = MicPermission.status }

    func copyUpdateCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateCheck.command, forType: .string)
        updateMessage = "Commande copiée — collez-la dans le Terminal."
    }

    func openRepo() {
        if let u = URL(string: AppInfo.repoURL) { NSWorkspace.shared.open(u) }
    }

    // MARK: Périphériques

    func engineClearSwitchNote() { engine.clearSwitchNote() }

    func setFollowOutput(_ on: Bool) {
        followOutput = on
        engine.followKeyboardOutput = on
        if on { engine.followKeyboardIfPossible() }
    }

    func refreshDevices() {
        audioDevices = CA.outputDevices().map { $0.1 }
        // Un instrument branché que macOS ne sait pas lire : on le nomme, au
        // lieu de laisser « aucun clavier détecté » envoyer chercher un câble.
        usbUnreadable = USBScan.proprietaryInstruments()
        micDevices = MicInput.inputDevices().map { (id: UInt32($0.0), name: $0.1) }
        if micDeviceID == 0, let first = micDevices.first { micDeviceID = first.id }
    }

    func chooseAudioDevice(_ name: String) {
        guard !engine.switchInFlight else { return }
        deviceNote = "Bascule vers « \(name) »…"
        objectWillChange.send()
        engine.switchAudioDevice(named: name) { [weak self] ok in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deviceNote = ok ? nil
                    : "« \(name) » n'a pas répondu. Éteignez puis rallumez l'appareil, "
                      + "ou débranchez et rebranchez son câble."
                self.refreshDevices()
                self.objectWillChange.send()
            }
        }
    }

    func toggleMic() {
        if micOn {
            engine.stopMic(); micOn = false; micMonitoring = false
            engine.mic.monitoring = false
            micPeakDB = -60
            micSilent = false; micSilentSince = nil
            micMessage = nil
            refreshRemoteSlow(force: true)
            return
        }
        guard micDeviceID != 0 else { micMessage = "Aucune entrée disponible."; return }
        micAuth = MicPermission.status
        switch micAuth {
        case .authorized:
            startMicNow()
        case .undetermined:
            micMessage = "macOS va demander l'autorisation du micro — répondez à sa fenêtre."
            MicPermission.request { [weak self] st in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.micAuth = st
                    if st == .authorized { self.startMicNow() }
                    else { self.micMessage = "Micro \(st.human). \(MicPermission.settingsHint)" }
                    self.refreshRemoteSlow(force: true)
                }
            }
        case .denied, .restricted:
            micMessage = "Micro \(micAuth.human). \(MicPermission.settingsHint)"
        }
        refreshRemoteSlow(force: true)
    }

    private func startMicNow() {
        guard engine.startMic(deviceID: micDeviceID) else {
            micMessage = engine.mic.lastError ?? "Entrée refusée."
            return
        }
        micOn = true
        syncMicChain()
        engine.mic.monitoring = micMonitoring
        micSilent = false
        micSilentSince = Date()
        micMessage = micMonitoring ? nil
            : "Micro ouvert, mais l'écoute est coupée : rien ne sort encore."
        refreshRemoteSlow(force: true)
    }

    func chooseMicDevice(_ id: UInt32) {
        let wasOn = micOn
        if micOn { toggleMic() }
        micDeviceID = id
        if wasOn { toggleMic() }
        refreshRemoteSlow(force: true)
    }

    func setMicGain(_ v: Float) { micGain = v; engine.mic.gain = v }
    func setMicComp(_ v: Float) { micComp = v; engine.mic.chain.compAmount = v }
    func setMicMonitoring(_ on: Bool) { micMonitoring = on; engine.mic.monitoring = on }
    func commitMicBands() { engine.mic.chain.updateEQ(micBands) }

    /// La chaîne du micro porte ses réglages dès le lancement, entrée ouverte
    /// ou non : l'analyseur du micro affiche sa courbe tout de suite, au lieu
    /// d'une ligne plate qui ne correspond pas aux tranches juste en dessous.
    private func syncMicChain() {
        engine.mic.gain = micGain
        engine.mic.chain.compAmount = micComp
        engine.mic.chain.updateEQ(micBands)
    }
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
    func setCheckUpdates(_ on: Bool) {
        engine.setCheckUpdates(on)
        objectWillChange.send()
        save()
    }

    func shutdown() { remote.stop(); save(); engine.shutdown() }
}

// MARK: - Écran de chargement

struct BootView: View {
    @ObservedObject var m: RigModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "pianokeys")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Tone.accent)
            VStack(spacing: 6) {
                Text("Piano Live Setup")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Tone.txt0)
                // Aucun nom de modèle en dur ici : l'outil marche avec le
                // clavier qu'on lui branche, quel qu'il soit.
                Text("Votre clavier MIDI, prêt à jouer")
                    .font(.system(size: 12))
                    .foregroundStyle(Tone.txt2)
            }
            if let e = m.fatalError {
                Text(e).font(.system(size: 12)).foregroundStyle(Tone.hot)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            } else if let hint = m.bootHint {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16)).foregroundStyle(Tone.warn)
                    Text(hint).font(.system(size: 12)).foregroundStyle(Tone.warn)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 48)
            } else {
                VStack(spacing: 8) {
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
                        .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                        .frame(height: 14)
                }
            }
            Spacer()
            Text("1,5 Go d'échantillons · chargement unique au lancement")
                .font(.system(size: 11)).foregroundStyle(Tone.txt2.opacity(0.7))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tone.bg0)
    }
}
