import Foundation

// Accelerate n'existe que chez Apple. Le reste de ce fichier — filtres, chaîne de
// traitement, analyse — est du Swift pur : compilé avec -DPLS_PORTABLE, il tourne
// partout où tourne Swift. C'est ce qui rend un portage envisageable.
#if canImport(Accelerate) && !PLS_PORTABLE
import Accelerate
#endif

// MARK: - Biquad (formules RBJ)

enum FilterKind: Int, Codable, CaseIterable {
    case highPass, lowShelf, peaking, highShelf, lowPass

    /// Nom stable, lisible, pour l'interface web : le code JavaScript
    /// recalcule la courbe avec les mêmes formules et a besoin du type.
    var tag: String {
        switch self {
        case .highPass:  return "highpass"
        case .lowShelf:  return "lowshelf"
        case .peaking:   return "peaking"
        case .highShelf: return "highshelf"
        case .lowPass:   return "lowpass"
        }
    }

    var label: String {
        switch self {
        case .highPass:  return "Coupe-bas"
        case .lowShelf:  return "Shelf grave"
        case .peaking:   return "Cloche"
        case .highShelf: return "Shelf aigu"
        case .lowPass:   return "Coupe-haut"
        }
    }
    var usesGain: Bool { self == .lowShelf || self == .peaking || self == .highShelf }
}

struct BiquadCoeffs {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static func make(_ kind: FilterKind, freq: Float, gainDB: Float, q: Float, sampleRate: Float) -> BiquadCoeffs {
        let f = max(10, min(freq, sampleRate * 0.49))
        let w0 = 2 * Float.pi * f / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let qq = max(0.1, q)
        let alpha = sn / (2 * qq)
        let A = pow(10, gainDB / 40)
        var b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float

        switch kind {
        case .highPass:
            b0 = (1 + cs) / 2;  b1 = -(1 + cs);  b2 = (1 + cs) / 2
            a0 = 1 + alpha;     a1 = -2 * cs;    a2 = 1 - alpha
        case .lowPass:
            b0 = (1 - cs) / 2;  b1 = 1 - cs;     b2 = (1 - cs) / 2
            a0 = 1 + alpha;     a1 = -2 * cs;    a2 = 1 - alpha
        case .peaking:
            b0 = 1 + alpha * A; b1 = -2 * cs;    b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cs;    a2 = 1 - alpha / A
        case .lowShelf:
            let beta = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cs + beta)
            b1 = 2 * A * ((A - 1) - (A + 1) * cs)
            b2 = A * ((A + 1) - (A - 1) * cs - beta)
            a0 = (A + 1) + (A - 1) * cs + beta
            a1 = -2 * ((A - 1) + (A + 1) * cs)
            a2 = (A + 1) + (A - 1) * cs - beta
        case .highShelf:
            let beta = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cs + beta)
            b1 = -2 * A * ((A - 1) + (A + 1) * cs)
            b2 = A * ((A + 1) + (A - 1) * cs - beta)
            a0 = (A + 1) - (A - 1) * cs + beta
            a1 = 2 * ((A - 1) - (A + 1) * cs)
            a2 = (A + 1) - (A - 1) * cs - beta
        }
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Module de la réponse en fréquence, en dB — sert aussi à dessiner la courbe.
    func magnitudeDB(at freq: Float, sampleRate: Float) -> Float {
        let w = 2 * Float.pi * freq / sampleRate
        let cw = cos(w), sw = sin(w)
        let c2w = cos(2 * w), s2w = sin(2 * w)
        let nr = b0 + b1 * cw + b2 * c2w
        let ni = -(b1 * sw + b2 * s2w)
        let dr = 1 + a1 * cw + a2 * c2w
        let di = -(a1 * sw + a2 * s2w)
        let num = sqrt(nr * nr + ni * ni)
        let den = max(1e-9, sqrt(dr * dr + di * di))
        return 20 * log10(max(1e-9, num / den))
    }
}

/// État d'un biquad, forme directe II transposée, un par canal.
struct BiquadState { var z1: Float = 0, z2: Float = 0 }

@inline(__always)
func biquadProcess(_ x: Float, _ c: BiquadCoeffs, _ s: inout BiquadState) -> Float {
    let y = c.b0 * x + s.z1
    s.z1 = c.b1 * x - c.a1 * y + s.z2
    s.z2 = c.b2 * x - c.a2 * y
    return y
}

// MARK: - Chaîne de traitement

let kEQBandCount = 7

/// Chaîne stéréo : drive → EQ 7 bandes → trémolo → compresseur → gain → limiteur.
///
/// Les coefficients vivent dans deux jeux alloués une fois pour toutes. L'interface
/// écrit dans le jeu inactif puis bascule un drapeau ; le thread audio ne lit jamais
/// un coefficient à moitié écrit, et aucun verrou n'est pris dans le rendu.
final class ProcessorChain: @unchecked Sendable {
    private let coeffs: UnsafeMutablePointer<BiquadCoeffs>   // 2 × kEQBandCount
    private let actives: UnsafeMutablePointer<Bool>          // 2 × kEQBandCount
    private let liveSet: UnsafeMutablePointer<Int>           // jeu lu par le thread audio
    private let stateL: UnsafeMutablePointer<BiquadState>
    private let stateR: UnsafeMutablePointer<BiquadState>

    var sampleRate: Float = 44100

    // Paramètres scalaires : une lecture déchirée n'a aucune conséquence audible.
    var drive: Float = 0
    var tremRate: Float = 0
    var tremDepth: Float = 0
    var compAmount: Float = 0
    var gain: Float = 1
    /// Désactivé pendant l'étalonnage, pour mesurer les vraies crêtes.
    var limiterEnabled = true
    private var tremPhase: Float = 0
    private var env: Float = 0
    private var lastBands: [EQBand] = defaultEQ()

    init() {
        coeffs = .allocate(capacity: 2 * kEQBandCount)
        coeffs.initialize(repeating: BiquadCoeffs(), count: 2 * kEQBandCount)
        actives = .allocate(capacity: 2 * kEQBandCount)
        actives.initialize(repeating: false, count: 2 * kEQBandCount)
        liveSet = .allocate(capacity: 1); liveSet.pointee = 0
        stateL = .allocate(capacity: kEQBandCount)
        stateL.initialize(repeating: BiquadState(), count: kEQBandCount)
        stateR = .allocate(capacity: kEQBandCount)
        stateR.initialize(repeating: BiquadState(), count: kEQBandCount)
    }

    func updateEQ(_ bands: [EQBand]) {
        lastBands = bands
        let target = 1 - liveSet.pointee            // on écrit dans le jeu inactif
        let base = target * kEQBandCount
        for i in 0..<kEQBandCount {
            let b = i < bands.count ? bands[i] : defaultEQ()[i]
            coeffs[base + i] = BiquadCoeffs.make(b.kind, freq: b.freq, gainDB: b.gain,
                                                 q: b.q, sampleRate: sampleRate)
            actives[base + i] = b.enabled && !(b.kind.usesGain && abs(b.gain) < 0.05)
        }
        liveSet.pointee = target                    // bascule
    }

    func reset() {
        for i in 0..<kEQBandCount { stateL[i] = BiquadState(); stateR[i] = BiquadState() }
        env = 0; tremPhase = 0
    }

    /// Courbe de réponse globale de l'EQ, pour l'affichage.
    func responseDB(freqs: [Float]) -> [Float] {
        let base = liveSet.pointee * kEQBandCount
        return freqs.map { f in
            var sum: Float = 0
            for i in 0..<kEQBandCount where actives[base + i] {
                sum += coeffs[base + i].magnitudeDB(at: f, sampleRate: sampleRate)
            }
            return sum
        }
    }

    /// Réponse d'une seule bande, pour tracer sa contribution.
    func bandResponseDB(_ index: Int, freqs: [Float]) -> [Float] {
        let base = liveSet.pointee * kEQBandCount
        guard index < kEQBandCount, actives[base + index] else { return freqs.map { _ in 0 } }
        return freqs.map { coeffs[base + index].magnitudeDB(at: $0, sampleRate: sampleRate) }
    }

    func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) {
        let base = liveSet.pointee * kEQBandCount
        let drv = drive
        let driveGain = 1 + drv * 7
        let driveComp = drv > 0.001 ? 1 / (1 + drv * 1.6) : 1
        let tRate = tremRate, tDepth = tremDepth
        let tInc = 2 * Float.pi * tRate / sampleRate
        let comp = compAmount
        let g = gain
        let ceiling: Float = 0.944
        let lim = limiterEnabled

        for i in 0..<frames {
            var a = l[i], b = r[i]

            if drv > 0.001 {
                a = tanhf(a * driveGain) * driveComp
                b = tanhf(b * driveGain) * driveComp
            }

            for k in 0..<kEQBandCount where actives[base + k] {
                a = biquadProcess(a, coeffs[base + k], &stateL[k])
                b = biquadProcess(b, coeffs[base + k], &stateR[k])
            }

            if tDepth > 0.001 && tRate > 0.01 {
                // Trémolo stéréo : les deux côtés en opposition, comme un Suitcase.
                let s = sinf(tremPhase)
                a *= 1 - tDepth * 0.5 * (1 - s)
                b *= 1 - tDepth * 0.5 * (1 + s)
                tremPhase += tInc
                if tremPhase > 2 * Float.pi { tremPhase -= 2 * Float.pi }
            }

            if comp > 0.001 {
                let peak = max(abs(a), abs(b))
                env += (peak > env ? 0.01 : 0.0006) * (peak - env)
                let threshold: Float = 0.08
                if env > threshold {
                    let ratio = 1 + comp * 5
                    let reduce = pow(env / threshold, (1 / ratio) - 1)
                    a *= reduce; b *= reduce
                }
                let makeup = 1 + comp * 0.8
                a *= makeup; b *= makeup
            }

            a *= g; b *= g
            if lim {
                if a > ceiling || a < -ceiling { a = ceiling * tanhf(a / ceiling) }
                if b > ceiling || b < -ceiling { b = ceiling * tanhf(b / ceiling) }
            }
            l[i] = a; r[i] = b
        }
    }
}

// MARK: - Analyseur de spectre

/// Tampon circulaire écrit par le thread audio, lu par l'interface.
/// Un seul écrivain, un seul lecteur : le léger déchirement possible est sans
/// conséquence pour un afficheur.
final class SpectrumTap: @unchecked Sendable {
    static let fftSize = 2048
    private let capacity = 8192
    private let buffer: UnsafeMutablePointer<Float>
    private let writeIndex: UnsafeMutablePointer<Int>

    private var window: [Float]
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imag = [Float](repeating: 0, count: fftSize / 2)
    private var scratch = [Float](repeating: 0, count: fftSize)

    #if canImport(Accelerate) && !PLS_PORTABLE
    private let fft: vDSP.FFT<DSPSplitComplex>
    #else
    private var portableReal = [Float](repeating: 0, count: fftSize)
    private var portableImag = [Float](repeating: 0, count: fftSize)
    private let bitReverse: [Int]
    #endif

    /// Bandes affichées, réparties logarithmiquement de 20 Hz à 20 kHz.
    let bandCount = 128
    private(set) var bandsDB: [Float]
    private(set) var peaksDB: [Float]
    /// Module brut par bin FFT — sert aux mesures de vérification.
    private(set) var binMag: [Float]
    private var binForBand: [(Int, Int)] = []
    var sampleRate: Float = 44100 { didSet { rebuildBands() } }

    init() {
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        writeIndex = .allocate(capacity: 1)
        writeIndex.pointee = 0

        // Fenêtre de Hann, écrite à la main pour ne dépendre de personne.
        let n = Self.fftSize
        window = (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n - 1)) }

        #if canImport(Accelerate) && !PLS_PORTABLE
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Float(n))),
                       radix: .radix2, ofType: DSPSplitComplex.self)!
        #else
        var rev = [Int](repeating: 0, count: n)
        let bits = Int(log2(Double(n)))
        for i in 0..<n {
            var x = i, r = 0
            for _ in 0..<bits { r = (r << 1) | (x & 1); x >>= 1 }
            rev[i] = r
        }
        bitReverse = rev
        #endif

        bandsDB = [Float](repeating: -100, count: bandCount)
        peaksDB = [Float](repeating: -100, count: bandCount)
        binMag = [Float](repeating: 0, count: n / 2)
        rebuildBands()
    }

    #if !(canImport(Accelerate) && !PLS_PORTABLE)
    /// FFT complexe radix-2 en place, écrite en Swift pur.
    /// Deux fois plus de travail que la FFT réelle d'Accelerate, mais un
    /// analyseur de 2048 points trente fois par seconde reste négligeable.
    private func portableFFT() {
        let n = Self.fftSize
        for i in 0..<n {
            portableReal[bitReverse[i]] = scratch[i]
            portableImag[bitReverse[i]] = 0
        }
        var len = 2
        while len <= n {
            let ang = -2 * Float.pi / Float(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var curR: Float = 1, curI: Float = 0
                for j in 0..<(len / 2) {
                    let a = i + j, b = i + j + len / 2
                    let tr = portableReal[b] * curR - portableImag[b] * curI
                    let ti = portableReal[b] * curI + portableImag[b] * curR
                    portableReal[b] = portableReal[a] - tr
                    portableImag[b] = portableImag[a] - ti
                    portableReal[a] += tr
                    portableImag[a] += ti
                    let nextR = curR * wr - curI * wi
                    curI = curR * wi + curI * wr
                    curR = nextR
                }
                i += len
            }
            len <<= 1
        }
        // Accelerate renvoie une FFT réelle d'amplitude double : on s'aligne
        // dessus pour que l'affichage et les mesures soient identiques.
        for b in 0..<(n / 2) {
            real[b] = portableReal[b] * 2
            imag[b] = portableImag[b] * 2
        }
    }
    #endif

    private func rebuildBands() {
        let nyquist = sampleRate / 2
        let fMin: Float = 20, fMax = min(20000, nyquist * 0.98)
        let binHz = sampleRate / Float(Self.fftSize)
        var map: [(Int, Int)] = []
        for i in 0..<bandCount {
            let f0 = fMin * pow(fMax / fMin, Float(i) / Float(bandCount))
            let f1 = fMin * pow(fMax / fMin, Float(i + 1) / Float(bandCount))
            let b0 = max(1, Int(f0 / binHz))
            let b1 = max(b0 + 1, min(Self.fftSize / 2 - 1, Int(f1 / binHz) + 1))
            map.append((b0, b1))
        }
        binForBand = map
    }

    func frequency(forBand i: Int) -> Float {
        let fMin: Float = 20, fMax = min(20000, sampleRate / 2 * 0.98)
        return fMin * pow(fMax / fMin, (Float(i) + 0.5) / Float(bandCount))
    }

    /// Appelé depuis le thread audio : simple copie, aucune allocation.
    @inline(__always)
    func write(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, frames: Int) {
        var w = writeIndex.pointee
        for i in 0..<frames {
            buffer[w] = (l[i] + r[i]) * 0.5
            w += 1
            if w >= capacity { w = 0 }
        }
        writeIndex.pointee = w
    }

    /// Fréquence dominante dans une plage, affinée par interpolation parabolique
    /// sur les bins voisins. Sert à vérifier que la transposition décale bien la hauteur.
    func dominantFrequency(between lo: Float, and hi: Float) -> Float {
        let binHz = sampleRate / Float(Self.fftSize)
        let b0 = max(1, Int(lo / binHz)), b1 = min(Self.fftSize / 2 - 2, Int(hi / binHz) + 1)
        guard b1 > b0 else { return 0 }
        var best = b0
        for b in b0...b1 where binMag[b] > binMag[best] { best = b }
        let a = binMag[best - 1], m = binMag[best], c = binMag[best + 1]
        let denom = a - 2 * m + c
        let delta = abs(denom) < 1e-9 ? 0 : 0.5 * (a - c) / denom
        return (Float(best) + delta) * binHz
    }

    /// Fondamentale, et non simple pic le plus fort : sur une note grave de piano
    /// la deuxième harmonique dépasse souvent la fondamentale, et un détecteur
    /// naïf se trompe d'une octave. On redescend donc tant qu'une sous-harmonique
    /// porte encore une énergie significative.
    func fundamentalFrequency(between lo: Float, and hi: Float) -> Float {
        let binHz = sampleRate / Float(Self.fftSize)
        var f = dominantFrequency(between: lo, and: hi)
        guard f > 0 else { return 0 }
        let peak = energyAt(f, binHz: binHz)
        for _ in 0..<3 {
            let half = f / 2
            guard half >= lo else { break }
            // 12 % du pic suffit : une fondamentale faible reste une fondamentale.
            if energyAt(half, binHz: binHz) > peak * 0.12 { f = half } else { break }
        }
        return f
    }

    /// Énergie au voisinage immédiat d'une fréquence (trois bins), en linéaire.
    private func energyAt(_ freq: Float, binHz: Float) -> Float {
        let b = Int((freq / binHz).rounded())
        guard b > 0, b < Self.fftSize / 2 - 1 else { return 0 }
        return max(binMag[b - 1], max(binMag[b], binMag[b + 1]))
    }

    /// Énergie moyenne, en dB, dans une plage de fréquences. Sert à vérifier l'EQ.
    func energyDB(between lo: Float, and hi: Float) -> Float {
        let binHz = sampleRate / Float(Self.fftSize)
        let b0 = max(1, Int(lo / binHz)), b1 = min(Self.fftSize / 2 - 1, Int(hi / binHz) + 1)
        guard b1 > b0 else { return -120 }
        var acc: Double = 0
        for b in b0..<b1 { acc += Double(binMag[b] * binMag[b]) }
        return 10 * log10(max(1e-12, Float(acc / Double(b1 - b0))))
    }

    /// Remplit l'analyseur d'un spectre plausible — uniquement pour le rendu
    /// hors écran de l'interface, jamais utilisé en fonctionnement normal.
    var testSignalMode = false
    func injectTestSignal() {
        testSignalMode = true
        for i in 0..<bandCount {
            let f = frequency(forBand: i)
            let tilt = -9 * log10(max(f, 20) / 80)
            let bumps = 7 * exp(-pow((log10(f) - log10(220)) / 0.16, 2))
                      + 5 * exp(-pow((log10(f) - log10(880)) / 0.12, 2))
                      + 3 * exp(-pow((log10(f) - log10(2600)) / 0.14, 2))
            let ripple = 3.5 * sin(Float(i) * 1.7) + 2.0 * sin(Float(i) * 0.41)
            bandsDB[i] = max(-72, -22 + tilt + bumps + ripple)
            peaksDB[i] = bandsDB[i] + 3.5
        }
    }

    /// Appelé depuis l'interface, ~30 fois par seconde.
    func analyse() {
        if testSignalMode { return }
        let n = Self.fftSize
        var w = writeIndex.pointee - n
        if w < 0 { w += capacity }
        for i in 0..<n {
            var idx = w + i
            if idx >= capacity { idx -= capacity }
            scratch[i] = buffer[idx]
        }
        for i in 0..<n { scratch[i] *= window[i] }

        #if canImport(Accelerate) && !PLS_PORTABLE
        scratch.withUnsafeBufferPointer { sp in
            sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                        fft.forward(input: split, output: &split)
                    }
                }
            }
        }
        #else
        portableFFT()
        #endif

        let norm = 2.0 / Float(n)
        for b in 0..<(n / 2) {
            let re = real[b] * norm, im = imag[b] * norm
            binMag[b] = sqrt(re * re + im * im)
        }
        for i in 0..<bandCount {
            let (b0, b1) = binForBand[i]
            var acc: Float = 0
            for b in b0..<b1 { acc = max(acc, binMag[b]) }
            let db = 20 * log10(max(acc, 1e-7))
            // Lissage : montée rapide, descente lente, comme un analyseur de console.
            let prev = bandsDB[i]
            bandsDB[i] = db > prev ? db : prev + (db - prev) * 0.28
            peaksDB[i] = max(bandsDB[i], peaksDB[i] - 0.9)
        }
    }
}
