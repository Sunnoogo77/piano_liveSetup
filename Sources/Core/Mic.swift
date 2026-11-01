import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

// L'autorisation du micro, à part. Sur macOS, un programme qui ouvre une
// entrée audio doit :
//   1. porter la clé NSMicrophoneUsageDescription dans son Info.plist ;
//   2. demander l'autorisation explicitement.
// Sans le premier point, le système ne demande rien et l'entrée reste muette
// — le périphérique s'ouvre, le démarrage réussit, et il n'arrive que des
// zéros. C'était exactement le symptôme : « le micro ne passe pas », sans
// aucun message d'erreur.

enum MicPermission {

    enum Status: String {
        case authorized, denied, restricted, undetermined

        var human: String {
            switch self {
            case .authorized:   return "autorisé"
            case .denied:       return "refusé dans Réglages Système"
            case .restricted:   return "interdit par une règle de l'appareil"
            case .undetermined: return "pas encore demandé"
            }
        }
    }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .undetermined
        @unknown default:    return .undetermined
        }
    }

    /// Demande l'autorisation si elle n'a jamais été demandée. macOS affiche
    /// alors sa fenêtre ; il n'y a pas moyen de l'éviter, et c'est tant mieux.
    static func request(_ done: @escaping @Sendable (Status) -> Void) {
        guard status == .undetermined else { done(status); return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { done(status) }
        }
    }

    /// Le chemin exact à donner à quelqu'un dont l'autorisation est refusée.
    static let settingsHint =
        "Réglages Système → Confidentialité et sécurité → Microphone, "
        + "puis cochez Piano Live Setup."
}

// Entrée micro. Le micro est presque toujours sur un autre périphérique que la
// sortie (micro intégré du Mac, interface USB…), donc deux horloges différentes.
// On lit l'entrée dans un tampon circulaire et le rendu de sortie y puise à un
// pas fractionnaire, légèrement asservi au remplissage : cela absorbe à la fois
// la différence de fréquence d'échantillonnage et la dérive entre horloges.

final class MicInput: @unchecked Sendable {

    private(set) var deviceID: AudioObjectID = 0
    private(set) var deviceName = "—"
    private(set) var inputSampleRate: Double = 48000
    private(set) var channels = 1
    private(set) var running = false
    private(set) var lastError: String?

    private var procID: AudioDeviceIOProcID?

    private let capacity = 1 << 16
    private let ring: UnsafeMutablePointer<Float>
    private let writePos: UnsafeMutablePointer<Int>
    private var readPos: Double = 0
    private var outputSampleRate: Double = 44100

    /// Niveau d'entrée brut, pour le vumètre.
    private let inPeak: UnsafeMutablePointer<Float>

    let chain = ProcessorChain()
    /// Analyseur de l'entrée, avant gain et avant égalisation : c'est ce que
    /// le micro entend. Il tourne même quand l'écoute est coupée — on règle
    /// presque toujours une voix sans la renvoyer dans les haut-parleurs.
    let spectrum = SpectrumTap()
    var gain: Float = 1
    /// Coupé par défaut : un micro ouvert près des haut-parleurs du piano siffle.
    var monitoring = false

    init() {
        ring = .allocate(capacity: capacity)
        ring.initialize(repeating: 0, count: capacity)
        writePos = .allocate(capacity: 1); writePos.pointee = 0
        inPeak = .allocate(capacity: 1); inPeak.pointee = 0
        chain.limiterEnabled = false
    }

    var inputPeak: Float { inPeak.pointee }

    // MARK: Périphériques

    static func inputDevices() -> [(AudioObjectID, String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.compactMap { id in inChannels(id) > 0 ? (id, CA.deviceName(id)) : nil }
    }

    static func inChannels(_ id: AudioObjectID) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: kAudioObjectPropertyScopeInput,
                                           mElement: kAudioObjectPropertyElementMain)
        var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &sz) == noErr, sz > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(sz), alignment: 8)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, buf) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func inputFormat(_ id: AudioObjectID) -> AudioStreamBasicDescription? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                           mScope: kAudioObjectPropertyScopeInput,
                                           mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &asbd) == noErr else { return nil }
        return asbd
    }

    // MARK: Marche / arrêt

    func start(deviceID id: AudioObjectID, outputSampleRate osr: Double) -> Bool {
        stop()
        guard let fmt = Self.inputFormat(id) else {
            lastError = "format d'entrée illisible"; return false
        }
        deviceID = id
        deviceName = CA.deviceName(id)
        inputSampleRate = fmt.mSampleRate > 0 ? fmt.mSampleRate : 48000
        channels = max(1, Int(fmt.mChannelsPerFrame))
        outputSampleRate = osr
        chain.sampleRate = Float(osr)
        spectrum.sampleRate = Float(inputSampleRate)
        spectrum.reset()
        writePos.pointee = 0
        readPos = 0

        let ringPtr = ring, wPtr = writePos, cap = capacity, ch = channels, peakPtr = inPeak
        let tap = spectrum
        var pid: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&pid, id, nil) { _, inData, _, _, _ in
            let bufs = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inData))
            guard let first = bufs.first, let data = first.mData else { return }
            let interleavedChannels = Int(first.mNumberChannels)
            let frames = Int(first.mDataByteSize) / 4 / max(1, interleavedChannels)
            let p = data.assumingMemoryBound(to: Float.self)
            var w = wPtr.pointee
            var peak: Float = 0
            for i in 0..<frames {
                // Micro pris en mono : on moyenne les voies présentes.
                var v: Float = 0
                if interleavedChannels <= 1 {
                    v = p[i]
                } else {
                    for c in 0..<interleavedChannels { v += p[i * interleavedChannels + c] }
                    v /= Float(interleavedChannels)
                }
                if abs(v) > peak { peak = abs(v) }
                tap.push(v)
                ringPtr[w] = v
                w += 1; if w >= cap { w = 0 }
            }
            _ = ch
            peakPtr.pointee = peak
            wPtr.pointee = w
        }
        guard st == noErr, let pid else {
            lastError = "impossible d'ouvrir le périphérique (\(st))"; return false
        }
        procID = pid
        let started = AudioDeviceStart(id, pid)
        guard started == noErr else {
            lastError = "démarrage refusé (\(started)) — autorisation micro ?"
            AudioDeviceDestroyIOProcID(id, pid); procID = nil
            return false
        }
        readPos = Double(writePos.pointee)
        running = true
        lastError = nil
        return true
    }

    func stop() {
        if let pid = procID, deviceID != 0 {
            AudioDeviceStop(deviceID, pid)
            AudioDeviceDestroyIOProcID(deviceID, pid)
        }
        procID = nil
        running = false
        inPeak.pointee = 0
        spectrum.reset()
    }

    // MARK: Lecture depuis le rendu de sortie

    private var scratchL = [Float](repeating: 0, count: 4096)
    private var scratchR = [Float](repeating: 0, count: 4096)

    /// Mélange le micro, traité, dans les tampons de sortie.
    @inline(__always)
    func mix(into l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) {
        guard running, monitoring, frames <= scratchL.count else { return }

        let w = Double(writePos.pointee)
        var fill = w - readPos
        if fill < 0 { fill += Double(capacity) }
        let target = Double(frames) * 3                 // trois blocs d'avance
        // Asservissement très doux : ±0,2 % suffisent à rattraper la dérive.
        let error = (fill - target) / target
        let rate = (inputSampleRate / outputSampleRate) * (1 + max(-0.002, min(0.002, error * 0.05)))

        // Pas assez de matière : on laisse le tampon se remplir plutôt que de hacher.
        guard fill > Double(frames) * rate + 4 else { return }

        scratchL.withUnsafeMutableBufferPointer { lp in
            scratchR.withUnsafeMutableBufferPointer { rp in
                var pos = readPos
                for i in 0..<frames {
                    let i0 = Int(pos) % capacity
                    let i1 = (i0 + 1) % capacity
                    let frac = Float(pos - pos.rounded(.down))
                    let v = ring[i0] * (1 - frac) + ring[i1] * frac
                    lp[i] = v; rp[i] = v
                    pos += rate
                    if pos >= Double(capacity) { pos -= Double(capacity) }
                }
                readPos = pos
                chain.gain = gain
                chain.process(lp.baseAddress!, rp.baseAddress!, frames: frames)
                for i in 0..<frames {
                    l[i] += lp[i]
                    r[i] += rp[i]
                }
            }
        }
    }
}
