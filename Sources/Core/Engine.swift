import Foundation
import AVFoundation
import CoreAudio
import CoreMIDI

// MARK: - Utilitaires CoreAudio

enum CA {
    static func outputDevices() -> [(AudioObjectID, String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.compactMap { id in outChannels(id) > 0 ? (id, deviceName(id)) : nil }
    }

    static func deviceName(_ id: AudioObjectID) -> String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var nm: Unmanaged<CFString>?
        var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &nm) == noErr, let nm else { return "?" }
        return nm.takeRetainedValue() as String
    }

    static func outChannels(_ id: AudioObjectID) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: kAudioObjectPropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &sz) == noErr, sz > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(sz), alignment: 8)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, buf) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func sampleRate(_ id: AudioObjectID) -> Double {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var sr: Float64 = 44100
        var sz = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &sr)
        return sr
    }

    static func bufferFrames(_ id: AudioObjectID) -> UInt32 {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &v)
        return v
    }

    @discardableResult
    static func setBufferFrames(_ id: AudioObjectID, _ frames: UInt32) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var v = frames
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }
}

// MARK: - Choix automatique des périphériques

enum DevicePicker {
    /// Beaucoup de pianos numériques se présentent au Mac à la fois comme port
    /// MIDI et comme carte son, sous le même nom. Quand c'est le cas on choisit
    /// cette sortie : un seul câble fait tout. Sinon, la sortie par défaut.
    static func audioOutput(preferring wanted: String, midiNames: [String]) -> (AudioObjectID, String)? {
        let outs = CA.outputDevices()
        guard !outs.isEmpty else { return nil }
        if !wanted.isEmpty,
           let exact = outs.first(where: { $0.1.localizedCaseInsensitiveContains(wanted) }) {
            return exact
        }
        for name in midiNames {
            let key = name.lowercased()
            if let match = outs.first(where: {
                let d = $0.1.lowercased()
                return d.contains(key) || key.contains(d)
            }) { return match }
        }
        if let def = defaultOutput(), let d = outs.first(where: { $0.0 == def }) { return d }
        return outs.first
    }

    static func defaultOutput() -> AudioObjectID? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var id: AudioObjectID = 0
        var sz = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &id) == noErr
        else { return nil }
        return id
    }

    /// Les ports MIDI purement logiciels ne sont pas des claviers.
    static func looksLikeSoftwarePort(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("iac") || n.contains("bus") || n.contains("network")
            || n.contains("session") || n.contains("virtual")
    }
}

// MARK: - Moteur

final class LiveEngine: @unchecked Sendable {

    static let maxLayers = 3

    private var settings: OpaquePointer?
    private var synth: OpaquePointer?
    private var sfIDs: [String: Int32] = [:]

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var deviceID: AudioObjectID = 0
    private var originalBufferFrames: UInt32 = 0

    private var midiClient = MIDIClientRef()
    private var midiIn = MIDIPortRef()
    private var midiOut = MIDIPortRef()
    private var pianoDestination: MIDIEndpointRef = 0

    let chain = ProcessorChain()
    let spectrum = SpectrumTap()
    let mic = MicInput()
    let audioRecorder = AudioFileRecorder()

    private(set) var config: RigConfig
    private(set) var presetIndex = 0
    var preset: Preset { config.presets[presetIndex] }

    var transpose: Int32 = 0
    var octave: Int32 = 0
    private var masterVolume: Float = 0.8
    private var layerMix: Float = 1
    /// Canaux réellement occupés par le preset courant : on n'envoie jamais
    /// d'événements aux autres, sous peine de saturer la file de FluidSynth.
    private var activeChannels: Int32 = 1

    /// note entrante → liste de (canal, note jouée), pour un relâchement toujours correct
    private var sounding = [UInt8: [(Int32, Int32)]]()
    private let noteLock = NSLock()

    /// Notes réellement entendues, pour l'affichage du clavier et des accords.
    private var displayNotes = Set<Int>()
    private let displayLock = NSLock()

    // Enregistrement MIDI de la prise en cours
    private var takeRecording = false
    private var takeStart: Double = 0
    private var takeNotes: [RecNote] = []
    private var takeCCs: [RecCC] = []
    private var takeOpen: [Int: Int] = [:]          // note -> index dans takeNotes
    private let takeLock = NSLock()

    /// Nombre d'appels du bloc de rendu : sert à vérifier que le périphérique
    /// tourne vraiment avant de déclarer la sortie prête.
    private let renderCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private let peakPtr = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    private let midiStampPtr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    private(set) var midiSourceNames: [String] = []
    private(set) var midiDestinationName = "—"
    private(set) var audioDeviceLabel = "—"
    var onSetupChanged: (() -> Void)?
    private var connected = Set<MIDIEndpointRef>()
    private var audioWatcherInstalled = false
    /// Quand un clavier apparaît et qu'il sait aussi recevoir l'audio, on bascule
    /// la sortie dessus. C'est ce qu'on veut sur scène : brancher, et jouer.
    var followKeyboardOutput = true
    private(set) var lastSwitchNote: String?
    private(set) var statusAudio = "—"
    private(set) var bufferFramesRunning: UInt32 = 0
    private(set) var sampleRate: Double = 44100
    private(set) var loadedBanks: [String] = []
    private(set) var failedBanks: [String] = []
    /// Banque absente -> remplacement effectivement utilisé, pour l'afficher.
    private(set) var substitutions: [String: String] = [:]

    var peakL: Float { peakPtr[0] }
    var peakR: Float { peakPtr[1] }
    var secondsSinceLastNote: Double { Date.timeIntervalSinceReferenceDate - midiStampPtr.pointee }

    init(config: RigConfig) {
        self.config = config
        self.masterVolume = config.masterVolume
        peakPtr[0] = 0; peakPtr[1] = 0
        midiStampPtr.pointee = 0
        renderCount.pointee = 0
    }

    // MARK: Démarrage

    /// Charge les banques. `progress` est appelé avec (nom, index, total).
    func loadBanks(progress: ((String, Int, Int) -> Void)? = nil) throws {
        guard let s = new_fluid_settings() else { throw Err("réglages FluidSynth indisponibles") }
        settings = s
        fluid_settings_setnum(s, "synth.gain", 1.0)
        fluid_settings_setint(s, "synth.polyphony", 512)
        fluid_settings_setint(s, "synth.reverb.active", 1)
        fluid_settings_setint(s, "synth.chorus.active", 1)
        fluid_settings_setnum(s, "synth.reverb.damp", 0.3)
        fluid_settings_setnum(s, "synth.reverb.level", 0.7)
        fluid_settings_setnum(s, "synth.reverb.room-size", 0.5)
        fluid_settings_setnum(s, "synth.reverb.width", 0.8)
        fluid_settings_setnum(s, "synth.chorus.depth", 3.6)
        fluid_settings_setnum(s, "synth.chorus.level", 0.55)
        fluid_settings_setint(s, "synth.chorus.nr", 4)
        fluid_settings_setnum(s, "synth.chorus.speed", 0.36)

        let target = DevicePicker.audioOutput(preferring: config.audioDeviceName, midiNames: [])
        if let target { sampleRate = CA.sampleRate(target.0) }
        fluid_settings_setnum(s, "synth.sample-rate", sampleRate)
        chain.sampleRate = Float(sampleRate)
        spectrum.sampleRate = Float(sampleRate)

        guard let sy = new_fluid_synth(s) else { throw Err("synthétiseur FluidSynth indisponible") }
        synth = sy

        let needed = Bank.all
        for (i, file) in needed.enumerated() {
            progress?(file, i, needed.count)
            let path = config.soundsDir + "/" + file
            guard FileManager.default.fileExists(atPath: path) else { failedBanks.append(file); continue }
            let id = fluid_synth_sfload(sy, path, 0)
            if id == FLUID_FAILED { failedBanks.append(file) } else {
                sfIDs[file] = id
                loadedBanks.append(file)
            }
        }
        progress?("", needed.count, needed.count)
        guard !sfIDs.isEmpty else {
            throw Err("aucune banque de sons trouvée dans \(config.soundsDir) — lancez scripts/fetch-soundbanks.sh")
        }
        for missing in failedBanks {
            if let r = resolver.resolve(BankRef(file: missing, sfBank: 0, program: 0)) {
                substitutions[missing] = r.file
            }
        }
    }

    func startAudio() throws {
        guard let sy = synth else { throw Err("moteur non initialisé") }
        let names = currentMIDISourceNames()
        guard let target = DevicePicker.audioOutput(preferring: config.audioDeviceName, midiNames: names)
        else { throw Err("aucune sortie audio disponible") }
        deviceID = target.0
        audioDeviceLabel = target.1
        originalBufferFrames = CA.bufferFrames(deviceID)

        let out = engine.outputNode
        try out.auAudioUnit.setDeviceID(deviceID)
        CA.setBufferFrames(deviceID, config.bufferFrames)
        let sr = CA.sampleRate(deviceID)
        sampleRate = sr
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else {
            throw Err("format audio invalide")
        }

        let dsp = chain
        let tap = spectrum
        let peakOut = peakPtr
        let micIn = mic
        let rec = audioRecorder
        let rendered = renderCount
        dsp.limiterEnabled = false        // le limiteur est désormais en bout de chaîne
        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, ablPtr -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(ablPtr)
            guard bufs.count >= 2,
                  let l = bufs[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            rendered.pointee &+= 1
            fluid_synth_write_float(sy, Int32(n), l, 0, 1, r, 0, 1)
            dsp.process(l, r, frames: n)
            micIn.mix(into: l, r, frames: n)

            // Limiteur général : il protège la somme instrument + micro.
            let ceiling: Float = 0.944
            var pl: Float = 0, pr: Float = 0
            for i in 0..<n {
                var a = l[i], b = r[i]
                if a > ceiling || a < -ceiling { a = ceiling * tanhf(a / ceiling) }
                if b > ceiling || b < -ceiling { b = ceiling * tanhf(b / ceiling) }
                l[i] = a; r[i] = b
                if abs(a) > pl { pl = abs(a) }
                if abs(b) > pr { pr = abs(b) }
            }
            peakOut[0] = pl; peakOut[1] = pr
            tap.write(l, r, frames: n)
            rec.append(l, r, frames: n)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: out, format: fmt)

        // Un périphérique qu'un autre client vient de relâcher accepte le
        // démarrage sans erreur mais ne fait jamais tourner le rendu : on
        // n'entend rien, indéfiniment. On vérifie donc que le bloc de rendu
        // est bien appelé, et on réessaie sinon.
        var attempt = 0
        while true {
            attempt += 1
            renderCount.pointee = 0
            try engine.start()
            var waited = 0
            while renderCount.pointee == 0 && waited < 60 {
                usleep(10_000); waited += 1          // jusqu'à 600 ms
            }
            if renderCount.pointee > 0 { break }
            engine.stop()
            guard attempt < 4 else {
                throw Err("la sortie « \(target.1) » ne démarre pas — elle est peut-être encore utilisée par une autre application")
            }
            usleep(300_000)
        }
        if attempt > 1 { lastSwitchNote = "Sortie « \(target.1) » démarrée au bout de \(attempt) tentatives" }

        if CA.bufferFrames(deviceID) != config.bufferFrames {
            CA.setBufferFrames(deviceID, config.bufferFrames)
        }
        bufferFramesRunning = CA.bufferFrames(deviceID)
        statusAudio = String(format: "%@ · %d Hz · %d éch. · %.1f ms",
                             target.1, Int(sr), bufferFramesRunning,
                             Double(bufferFramesRunning) / sr * 1000)
        mic.chain.sampleRate = Float(sr)
    }

    /// À appeler depuis le thread principal : CoreMIDI délivre ses notifications
    /// de branchement sur la run loop du thread qui a créé le client. Créé depuis
    /// une tâche de fond, le client n'en reçoit aucune et le branchement à chaud
    /// ne marche pas.
    func startMIDI() {
        assert(Thread.isMainThread, "startMIDI doit être appelé sur le thread principal")
        MIDIClientCreateWithBlock("PianoLiveSetup" as CFString, &midiClient) { [weak self] notif in
            if notif.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.rescanMIDI() }
            }
        }
        MIDIOutputPortCreate(midiClient, "out" as CFString, &midiOut)
        MIDIInputPortCreateWithProtocol(midiClient, "in" as CFString, ._1_0, &midiIn) { [weak self] evtList, _ in
            guard let self else { return }
            var pkt = evtList.pointee.packet
            for _ in 0..<evtList.pointee.numPackets {
                withUnsafeBytes(of: pkt.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    var i = 0
                    let count = Int(pkt.wordCount)
                    while i < count && i < words.count {
                        let w = words[i]
                        let mt = (w >> 28) & 0xF
                        if mt == 0x2 {
                            self.handleMIDI(status: UInt8((w >> 16) & 0xFF),
                                            d1: UInt8((w >> 8) & 0x7F),
                                            d2: UInt8(w & 0x7F))
                            i += 1
                        } else if mt <= 0x2 { i += 1 }
                        else if mt == 0x3 || mt == 0x4 { i += 2 }
                        else { i += 4 }
                    }
                }
                pkt = MIDIEventPacketNext(&pkt).pointee
            }
        }
        rescanMIDI()
        installAudioWatcher()
    }

    /// La carte son d'un piano n'apparaît qu'à son allumage : on surveille aussi
    /// la liste des périphériques audio, pas seulement les ports MIDI.
    private func installAudioWatcher() {
        guard !audioWatcherInstalled else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
                self?.followKeyboardIfPossible()
            }
        audioWatcherInstalled = (st == noErr)
    }

    /// Si un clavier est branché et qu'il se présente aussi comme carte son,
    /// on y envoie le son — sauf si l'utilisateur a choisi une autre sortie.
    func followKeyboardIfPossible() {
        guard followKeyboardOutput, !midiSourceNames.isEmpty else { onSetupChanged?(); return }
        let outs = CA.outputDevices()
        for name in midiSourceNames {
            let key = name.lowercased()
            guard let match = outs.first(where: {
                let d = $0.1.lowercased()
                return d.contains(key) || key.contains(d)
            }) else { continue }
            if match.1 != audioDeviceLabel {
                if switchAudioDevice(named: match.1) {
                    lastSwitchNote = "Sortie basculée sur « \(match.1) »"
                }
            }
            break
        }
        onSetupChanged?()
    }

    private func currentMIDISourceNames() -> [String] {
        (0..<MIDIGetNumberOfSources()).compactMap { i in
            var nm: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(MIDIGetSource(i), kMIDIPropertyDisplayName, &nm) == noErr,
                  let nm else { return nil }
            let n = nm.takeRetainedValue() as String
            return DevicePicker.looksLikeSoftwarePort(n) ? nil : n
        }
    }

    /// Se connecte à toutes les sources MIDI matérielles, quel que soit le fabricant,
    /// et retient la destination correspondante pour le Local Control.
    func rescanMIDI() {
        let hadNoKeyboard = midiSourceNames.isEmpty
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            var nm: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &nm)
            let name = (nm?.takeRetainedValue() as String?) ?? "MIDI \(i)"
            if DevicePicker.looksLikeSoftwarePort(name) { continue }
            names.append(name)
            if !connected.contains(src) {
                if MIDIPortConnectSource(midiIn, src, nil) == noErr { connected.insert(src) }
            }
        }
        midiSourceNames = names

        pianoDestination = 0
        midiDestinationName = "—"
        // On vise la destination qui porte le même nom que le clavier branché.
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            var nm: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(d, kMIDIPropertyDisplayName, &nm)
            let n = (nm?.takeRetainedValue() as String?) ?? ""
            if DevicePicker.looksLikeSoftwarePort(n) { continue }
            if names.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) {
                pianoDestination = d; midiDestinationName = n; break
            }
        }
        if pianoDestination == 0, MIDIGetNumberOfDestinations() > 0 {
            for i in 0..<MIDIGetNumberOfDestinations() {
                let d = MIDIGetDestination(i)
                var nm: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(d, kMIDIPropertyDisplayName, &nm)
                let n = (nm?.takeRetainedValue() as String?) ?? ""
                if !DevicePicker.looksLikeSoftwarePort(n) {
                    pianoDestination = d; midiDestinationName = n; break
                }
            }
        }
        if config.localControlOff && pianoDestination != 0 { setPianoLocalControl(false) }
        if hadNoKeyboard && !names.isEmpty {
            // Un clavier vient d'apparaître : on prend la main sur la sortie audio.
            followKeyboardIfPossible()
        } else {
            onSetupChanged?()
        }
    }

    /// Vrai quand aucun clavier matériel n'est visible.
    var hasKeyboard: Bool { !midiSourceNames.isEmpty }

    // MARK: Local Control du piano

    var canControlPianoLocal: Bool { pianoDestination != 0 }

    /// CC 122 : coupe (ou rétablit) le générateur de son interne du clavier.
    /// C'est un message MIDI standard, compris par tous les fabricants.
    /// Réversible, et non mémorisé par l'instrument à l'extinction.
    func setPianoLocalControl(_ on: Bool) {
        guard pianoDestination != 0 else { return }
        let value: UInt8 = on ? 127 : 0
        for ch in 0..<16 {
            var list = MIDIEventList()
            let pkt = MIDIEventListInit(&list, ._1_0)
            var word: UInt32 = (0x2 << 28) | (UInt32(0xB0 | ch) << 16) | (122 << 8) | UInt32(value)
            _ = MIDIEventListAdd(&list, 1024, pkt, 0, 1, &word)
            MIDISendEventList(midiOut, pianoDestination, &list)
        }
        config.localControlOff = !on
    }

    // MARK: Traitement MIDI

    private func handleMIDI(status: UInt8, d1: UInt8, d2: UInt8) {
        guard let sy = synth else { return }
        let kind = status & 0xF0
        let p = preset

        switch kind {
        case 0x90 where d2 > 0:
            let shift = Int(transpose) + Int(octave) * 12
            var targets: [(Int32, Int32)] = []
            let gamma = p.velocityGamma
            let vNorm = Float(d2) / 127
            let vOut = Int32(max(1, min(127, Int(127 * pow(vNorm, gamma)))))

            for (i, layer) in p.layers.prefix(Self.maxLayers).enumerated() {
                guard d1 >= layer.loKey, d1 <= layer.hiKey,
                      d2 >= layer.loVel, d2 <= layer.hiVel else { continue }
                let note = Int(d1) + shift + Int(layer.semitones)
                guard note >= 0, note <= 127 else { continue }
                targets.append((Int32(i), Int32(note)))
            }
            guard !targets.isEmpty else { return }

            noteLock.lock()
            if let prev = sounding[d1] {
                for (ch, n) in prev { fluid_synth_noteoff(sy, ch, n) }
            }
            sounding[d1] = targets
            noteLock.unlock()

            for (ch, n) in targets { fluid_synth_noteon(sy, ch, n, vOut) }
            midiStampPtr.pointee = Date.timeIntervalSinceReferenceDate

            // La hauteur « musicale » est celle de la première couche : c'est elle
            // qu'on affiche, qu'on analyse en accords et qu'on enregistre.
            let sounding = Int(targets[0].1)
            displayLock.lock(); displayNotes.insert(sounding); displayLock.unlock()
            recordNoteOn(sounding, velocity: Int(vOut))

        case 0x80, 0x90:
            noteLock.lock()
            let prev = sounding.removeValue(forKey: d1)
            noteLock.unlock()
            if let prev {
                for (ch, n) in prev { fluid_synth_noteoff(sy, ch, n) }
                if let first = prev.first {
                    displayLock.lock(); displayNotes.remove(Int(first.1)); displayLock.unlock()
                    recordNoteOff(Int(first.1))
                }
            }

        case 0xB0:
            if d1 == 7 || d1 == 10 || d1 == 91 || d1 == 93 { return }   // réservés au mixage interne
            if d1 == 120 || d1 == 123 { panic(); return }
            for ch in 0..<activeChannels { fluid_synth_cc(sy, ch, Int32(d1), Int32(d2)) }
            midiStampPtr.pointee = Date.timeIntervalSinceReferenceDate
            if d1 == 64 || d1 == 66 || d1 == 67 || d1 == 11 || d1 == 1 {
                recordCC(Int(d1), Int(d2))
            }

        case 0xE0:
            let value = Int32(d1) | (Int32(d2) << 7)
            for ch in 0..<activeChannels { fluid_synth_pitch_bend(sy, ch, value) }

        default:
            break
        }
    }

    // MARK: Presets

    private var resolver: BankResolver { BankResolver(sfIDs: sfIDs) }

    func selectPreset(_ index: Int) {
        guard let sy = synth, config.presets.indices.contains(index) else { return }
        presetIndex = index
        let p = config.presets[index]
        layerMix = p.layerMix
        activeChannels = Int32(min(p.layers.count, Self.maxLayers))

        for ch in 0..<Int32(Self.maxLayers) {
            fluid_synth_all_sounds_off(sy, ch)
            fluid_synth_cc(sy, ch, 7, 0)
        }
        noteLock.lock(); sounding.removeAll(); noteLock.unlock()
        displayLock.lock(); let previous = displayNotes; displayNotes.removeAll(); displayLock.unlock()
        for n in previous { recordNoteOff(n) }

        for (i, layer) in p.layers.prefix(Self.maxLayers).enumerated() {
            let ch = Int32(i)
            guard let r = resolver.resolve(layer.bank) else { continue }
            fluid_synth_program_select(sy, ch, r.id, r.bank, r.program)
            let vol = i == 0 ? layer.volume : layerMix
            fluid_synth_cc(sy, ch, 7, Int32(max(0, min(127, vol * 127))))
            fluid_synth_cc(sy, ch, 10, Int32(max(0, min(127, (layer.pan + 1) * 63.5))))
            fluid_synth_cc(sy, ch, 91, layer.reverb)
            fluid_synth_cc(sy, ch, 93, layer.chorus)
        }
        applyProcessing(p)
    }

    private func applyProcessing(_ p: Preset) {
        chain.updateEQ(p.eqBands)
        chain.drive = p.drive
        chain.tremRate = p.tremRate
        chain.tremDepth = p.tremDepth
        chain.compAmount = p.compAmount
        chain.gain = p.gain * masterVolume
        chain.reset()
    }

    // MARK: Réglages en direct

    func setMasterVolume(_ v: Float) {
        masterVolume = max(0, min(1, v))
        config.masterVolume = masterVolume
        chain.gain = preset.gain * masterVolume
    }
    var currentMasterVolume: Float { masterVolume }

    func setLayerMix(_ v: Float) {
        layerMix = max(0, min(1, v))
        config.presets[presetIndex].layerMix = layerMix
        guard let sy = synth, preset.layers.count > 1 else { return }
        fluid_synth_cc(sy, 1, 7, Int32(layerMix * 127))
    }
    var currentLayerMix: Float { layerMix }

    func updateEQBand(_ index: Int, freq: Float? = nil, gain: Float? = nil,
                      q: Float? = nil, enabled: Bool? = nil) {
        guard config.presets[presetIndex].eqBands.indices.contains(index) else { return }
        if let freq { config.presets[presetIndex].eqBands[index].freq = freq }
        if let gain { config.presets[presetIndex].eqBands[index].gain = gain }
        if let q { config.presets[presetIndex].eqBands[index].q = q }
        if let enabled { config.presets[presetIndex].eqBands[index].enabled = enabled }
        chain.updateEQ(config.presets[presetIndex].eqBands)
    }

    func resetEQ() {
        config.presets[presetIndex].eqBands = defaultEQ()
        chain.updateEQ(config.presets[presetIndex].eqBands)
    }

    func setDrive(_ v: Float)  { config.presets[presetIndex].drive = v; chain.drive = v }
    func setTremolo(rate: Float, depth: Float) {
        config.presets[presetIndex].tremRate = rate
        config.presets[presetIndex].tremDepth = depth
        chain.tremRate = rate; chain.tremDepth = depth
    }
    func setComp(_ v: Float) { config.presets[presetIndex].compAmount = v; chain.compAmount = v }

    func nudgeTranspose(_ d: Int32) { transpose = max(-12, min(12, transpose + d)) }
    func resetTranspose() { transpose = 0; octave = 0 }
    func nudgeOctave(_ d: Int32) { octave = max(-3, min(3, octave + d)) }

    /// Relâche tout sur les seuls canaux utilisés. Ne recharge pas le preset :
    /// les volumes de canal survivent à un all-sounds-off, et réémettre les
    /// programmes saturerait la file d'événements.
    func panic() {
        guard let sy = synth else { return }
        noteLock.lock(); sounding.removeAll(); noteLock.unlock()
        displayLock.lock(); let stuck = displayNotes; displayNotes.removeAll(); displayLock.unlock()
        for n in stuck { recordNoteOff(n) }
        for ch in 0..<max(activeChannels, 1) {
            fluid_synth_cc(sy, ch, 64, 0)
            fluid_synth_cc(sy, ch, 66, 0)
            fluid_synth_cc(sy, ch, 67, 0)
            fluid_synth_all_notes_off(sy, ch)
            fluid_synth_all_sounds_off(sy, ch)
        }
        chain.reset()
    }

    func rememberCurrent(_ name: String) { config.currentPreset = name }
    func clearSwitchNote() { lastSwitchNote = nil }
    func setRemoteEnabled(_ on: Bool) { config.remoteEnabled = on }
    func setRemoteKey(_ k: String) { config.remoteKey = k }

    var heldNotes: Int { noteLock.lock(); defer { noteLock.unlock() }; return sounding.count }

    func shutdown() {
        if pendingTakeID != nil { _ = stopTake(name: "", tempo: 120) }
        mic.stop()
        if config.localControlOff { setPianoLocalControl(true) }   // on rend le clavier à son propriétaire
        panic()
        engine.stop()
        if originalBufferFrames > 0 { CA.setBufferFrames(deviceID, originalBufferFrames) }
    }

    // MARK: Notes tenues

    var soundingNotes: [Int] {
        displayLock.lock(); defer { displayLock.unlock() }
        return displayNotes.sorted()
    }

    var currentChord: ChordResult {
        ChordDetector.detect(soundingNotes)
    }

    // MARK: Enregistrement

    private func now() -> Double { Date.timeIntervalSinceReferenceDate }

    private func recordNoteOn(_ note: Int, velocity: Int) {
        takeLock.lock(); defer { takeLock.unlock() }
        guard takeRecording else { return }
        let t = now() - takeStart
        if let open = takeOpen[note], takeNotes[open].end <= takeNotes[open].start {
            takeNotes[open].end = t
        }
        takeNotes.append(RecNote(note: note, velocity: velocity, start: t, end: t))
        takeOpen[note] = takeNotes.count - 1
    }

    private func recordNoteOff(_ note: Int) {
        takeLock.lock(); defer { takeLock.unlock() }
        guard takeRecording, let idx = takeOpen[note] else { return }
        takeNotes[idx].end = now() - takeStart
        takeOpen[note] = nil
    }

    private func recordCC(_ cc: Int, _ value: Int) {
        takeLock.lock(); defer { takeLock.unlock() }
        guard takeRecording else { return }
        takeCCs.append(RecCC(cc: cc, value: value, time: now() - takeStart))
    }

    var isRecording: Bool { takeLock.lock(); defer { takeLock.unlock() }; return takeRecording }
    var recordedSeconds: Double {
        takeLock.lock(); defer { takeLock.unlock() }
        return takeRecording ? now() - takeStart : 0
    }
    var recordedNoteCount: Int { takeLock.lock(); defer { takeLock.unlock() }; return takeNotes.count }

    /// Démarre une prise. `withAudio` ajoute le WAV à côté du MIDI.
    func startTake(withAudio: Bool) -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH'h'mm'm'ss"
        let id = stamp.string(from: Date())
        let dir = TakeStore.folder(id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        takeLock.lock()
        takeNotes.removeAll(); takeCCs.removeAll(); takeOpen.removeAll()
        takeStart = now()
        takeRecording = true
        takeLock.unlock()

        if withAudio {
            try? audioRecorder.start(url: dir.appendingPathComponent("audio.wav"), sampleRate: sampleRate)
        }
        pendingTakeID = id
        return dir
    }
    private var pendingTakeID: String?

    /// Arrête la prise et écrit les quatre fichiers. Renvoie la fiche de la prise.
    func stopTake(name: String, tempo: Double) -> TakeMeta? {
        guard let id = pendingTakeID else { return nil }
        audioRecorder.stop()
        takeLock.lock()
        takeRecording = false
        let end = now() - takeStart
        for (_, idx) in takeOpen where takeNotes[idx].end <= takeNotes[idx].start {
            takeNotes[idx].end = end
        }
        takeOpen.removeAll()
        let notes = takeNotes.filter { $0.end > $0.start }
        let ccs = takeCCs
        takeLock.unlock()
        pendingTakeID = nil

        let dir = TakeStore.folder(id)
        let hasAudio = FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.wav").path)
        guard !notes.isEmpty || hasAudio else {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }

        let meta = TakeMeta(id: id, name: name.isEmpty ? id : name, date: Date(),
                            duration: max(end, notes.map { $0.end }.max() ?? 0),
                            preset: preset.name, transpose: Int(transpose) + Int(octave) * 12,
                            tempo: tempo, noteCount: notes.count, hasAudio: hasAudio)
        let take = Take(meta: meta, notes: notes, ccs: ccs)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(take).write(to: dir.appendingPathComponent("prise.json"))
        try? MIDIFileWriter.data(take: take).write(to: dir.appendingPathComponent("performance.mid"))
        try? ScoreWriter.musicXML(take: take)
            .write(to: dir.appendingPathComponent("partition.musicxml"), atomically: true, encoding: .utf8)
        let grid = ChordTimeline.build(notes)
        try? ChordTimeline.text(grid, take: meta)
            .write(to: dir.appendingPathComponent("accords.txt"), atomically: true, encoding: .utf8)
        return meta
    }

    // MARK: Changement de sortie audio en cours de route

    func switchAudioDevice(named name: String) -> Bool {
        guard let target = CA.outputDevices().first(where: { $0.1 == name }) else { return false }
        panic()
        engine.stop()
        if originalBufferFrames > 0 { CA.setBufferFrames(deviceID, originalBufferFrames) }
        if let node = sourceNode { engine.detach(node); sourceNode = nil }
        config.audioDeviceName = name
        do { try startAudio() } catch { return false }
        selectPreset(presetIndex)
        if mic.running { _ = mic.start(deviceID: mic.deviceID, outputSampleRate: sampleRate) }
        _ = target
        return true
    }

    // MARK: Micro

    @discardableResult
    func startMic(deviceID id: AudioObjectID) -> Bool {
        mic.start(deviceID: id, outputSampleRate: sampleRate)
    }
    func stopMic() { mic.stop() }

    /// Point d'entrée de test : injecte un message MIDI comme s'il venait du clavier.
    func injectMIDI(status: UInt8, d1: UInt8, d2: UInt8) { handleMIDI(status: status, d1: d1, d2: d2) }

    struct Err: LocalizedError {
        let msg: String
        init(_ m: String) { msg = m }
        var errorDescription: String? { msg }
    }
}
