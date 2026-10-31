import Foundation

// Enregistrement d'une prise : l'audio tel qu'il sort, le MIDI tel qu'il a été
// joué, et une partition quantifiée. Trois formats pour trois usages.

// MARK: - Données d'une prise

struct RecNote: Codable, Hashable {
    var note: Int          // hauteur réellement entendue (transposition comprise)
    var velocity: Int
    var start: Double      // secondes depuis le début de la prise
    var end: Double
    var duration: Double { max(0.02, end - start) }
}

struct RecCC: Codable, Hashable {
    var cc: Int
    var value: Int
    var time: Double
}

struct TakeMeta: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var date: Date
    var duration: Double
    var preset: String
    var transpose: Int
    var tempo: Double
    var noteCount: Int
    var hasAudio: Bool
}

struct Take: Codable {
    var meta: TakeMeta
    var notes: [RecNote]
    var ccs: [RecCC]
}

// MARK: - Dossier des prises

enum TakeStore {
    static var root: URL {
        AppPaths.recordings
    }
    static func folder(_ id: String) -> URL { root.appendingPathComponent(id) }

    static func list() -> [TakeMeta] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return items.compactMap { dir -> TakeMeta? in
            let f = dir.appendingPathComponent("prise.json")
            guard let d = try? Data(contentsOf: f),
                  let t = try? dec.decode(Take.self, from: d) else { return nil }
            return t.meta
        }.sorted { $0.date > $1.date }
    }

    static func load(_ id: String) -> Take? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("prise.json")) else { return nil }
        return try? dec.decode(Take.self, from: d)
    }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: folder(id)) }
}

// MARK: - Écriture audio (WAV 24 bits)

/// Tampon circulaire écrit par le thread audio, vidé vers le disque par un thread
/// dédié : jamais d'accès fichier depuis le rendu.
final class AudioFileRecorder: @unchecked Sendable {
    private let capacity = 1 << 20                  // ~5,9 s en stéréo à 44,1 kHz
    private let ring: UnsafeMutablePointer<Float>
    private let writePos: UnsafeMutablePointer<Int>
    private let recording: UnsafeMutablePointer<Bool>
    private var readPos = 0
    private var handle: FileHandle?
    private var dataBytes = 0
    private var sampleRate: Double = 44100
    private(set) var url: URL?
    private var worker: Thread?

    init() {
        ring = .allocate(capacity: capacity)
        ring.initialize(repeating: 0, count: capacity)
        writePos = .allocate(capacity: 1); writePos.pointee = 0
        recording = .allocate(capacity: 1); recording.pointee = false
    }

    var isRecording: Bool { recording.pointee }

    /// Appelé depuis le thread audio : copie seulement, aucune allocation.
    @inline(__always)
    func append(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, frames: Int) {
        guard recording.pointee else { return }
        var w = writePos.pointee
        for i in 0..<frames {
            ring[w] = l[i]; w += 1; if w >= capacity { w = 0 }
            ring[w] = r[i]; w += 1; if w >= capacity { w = 0 }
        }
        writePos.pointee = w
    }

    func start(url: URL, sampleRate: Double) throws {
        self.sampleRate = sampleRate
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle?.write(contentsOf: Self.header(sampleRate: sampleRate, dataBytes: 0))
        dataBytes = 0
        readPos = writePos.pointee
        recording.pointee = true
        let t = Thread { [weak self] in self?.drainLoop() }
        t.qualityOfService = .utility
        worker = t
        t.start()
    }

    func stop() {
        guard recording.pointee else { return }
        recording.pointee = false
        Thread.sleep(forTimeInterval: 0.12)      // laisse le thread vider le reste
        drain()
        if let h = handle {
            try? h.seek(toOffset: 0)
            try? h.write(contentsOf: Self.header(sampleRate: sampleRate, dataBytes: dataBytes))
            try? h.close()
        }
        handle = nil
    }

    private func drainLoop() {
        while recording.pointee {
            drain()
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func drain() {
        let w = writePos.pointee
        var available = w - readPos
        if available < 0 { available += capacity }
        guard available > 0, let h = handle else { return }
        var bytes = [UInt8]()
        bytes.reserveCapacity(available * 3)
        var p = readPos
        for _ in 0..<available {
            let v = max(-1.0, min(1.0, ring[p]))
            let i = Int32(v * 8_388_607)
            bytes.append(UInt8(truncatingIfNeeded: i))
            bytes.append(UInt8(truncatingIfNeeded: i >> 8))
            bytes.append(UInt8(truncatingIfNeeded: i >> 16))
            p += 1; if p >= capacity { p = 0 }
        }
        readPos = p
        try? h.write(contentsOf: Data(bytes))
        dataBytes += bytes.count
    }

    private static func header(sampleRate: Double, dataBytes: Int) -> Data {
        var d = Data()
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: Int) { var x = UInt32(truncatingIfNeeded: v); d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(truncatingIfNeeded: v); d.append(Data(bytes: &x, count: 2)) }
        let channels = 2, bits = 24
        let byteRate = Int(sampleRate) * channels * bits / 8
        str("RIFF"); u32(36 + dataBytes); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(channels)
        u32(Int(sampleRate)); u32(byteRate); u16(channels * bits / 8); u16(bits)
        str("data"); u32(dataBytes)
        return d
    }
}

// MARK: - Fichier MIDI standard

enum MIDIFileWriter {
    /// SMF type 1, 480 tops par noire. Le timing réel est conservé tel quel :
    /// le fichier rejoue exactement ce qui a été joué.
    static func data(take: Take) -> Data {
        let ppq = 480
        let tempo = max(30, min(300, take.meta.tempo))
        let ticksPerSecond = Double(ppq) * tempo / 60

        struct Ev { var tick: Int; var order: Int; var bytes: [UInt8] }
        var events: [Ev] = []
        for n in take.notes {
            let onTick = Int(n.start * ticksPerSecond)
            let offTick = max(onTick + 1, Int(n.end * ticksPerSecond))
            events.append(Ev(tick: onTick, order: 1,
                             bytes: [0x90, UInt8(max(0, min(127, n.note))), UInt8(max(1, min(127, n.velocity)))]))
            events.append(Ev(tick: offTick, order: 0,
                             bytes: [0x80, UInt8(max(0, min(127, n.note))), 0]))
        }
        for c in take.ccs {
            events.append(Ev(tick: Int(c.time * ticksPerSecond), order: 2,
                             bytes: [0xB0, UInt8(c.cc), UInt8(max(0, min(127, c.value)))]))
        }
        events.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }

        func vlq(_ value: Int) -> [UInt8] {
            var v = max(0, value)
            var out: [UInt8] = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 { out.insert(UInt8((v & 0x7F) | 0x80), at: 0); v >>= 7 }
            return out
        }
        func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
            var out = Array(name.utf8)
            let n = body.count
            out += [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
            return out + body
        }

        // Piste 0 : tempo, mesure, nom
        var meta: [UInt8] = []
        let usPerQuarter = Int(60_000_000 / tempo)
        meta += vlq(0) + [0xFF, 0x51, 0x03,
                          UInt8((usPerQuarter >> 16) & 0xFF),
                          UInt8((usPerQuarter >> 8) & 0xFF),
                          UInt8(usPerQuarter & 0xFF)]
        meta += vlq(0) + [0xFF, 0x58, 0x04, 4, 2, 24, 8]
        let title = Array(take.meta.name.utf8).prefix(120)
        meta += vlq(0) + [0xFF, 0x03, UInt8(title.count)] + title
        meta += vlq(0) + [0xFF, 0x2F, 0x00]

        // Piste 1 : la performance
        var perf: [UInt8] = []
        let instr = Array("Piano — \(take.meta.preset)".utf8).prefix(120)
        perf += vlq(0) + [0xFF, 0x04, UInt8(instr.count)] + instr
        var last = 0
        for e in events {
            perf += vlq(e.tick - last) + e.bytes
            last = e.tick
        }
        perf += vlq(0) + [0xFF, 0x2F, 0x00]

        let header: [UInt8] = [0, 1, 0, 2, UInt8((ppq >> 8) & 0xFF), UInt8(ppq & 0xFF)]
        return Data(chunk("MThd", header) + chunk("MTrk", meta) + chunk("MTrk", perf))
    }
}

// MARK: - Partition (MusicXML)

enum ScoreWriter {

    struct Slice {
        var notes: [Int]
        var startBeats: Double
        var lengthBeats: Double
        var isRest: Bool { notes.isEmpty }
    }

    /// Quantifie une prise et la découpe en tranches par portée.
    /// Une performance libre n'a pas de rythme exact : on arrondit à la double
    /// croche. C'est une transcription lisible, pas une copie au millième.
    static func slices(_ notes: [RecNote], tempo: Double, splitAt: Int,
                       upper: Bool, totalBeats: Double) -> [Slice] {
        let grid = 0.25                                   // double croche
        let beatsPerSecond = tempo / 60
        func q(_ t: Double) -> Double { (t * beatsPerSecond / grid).rounded() * grid }

        let staffNotes = notes.filter { upper ? $0.note >= splitAt : $0.note < splitAt }
        var onsets: [Double: [Int]] = [:]
        var lengths: [Double: Double] = [:]
        for n in staffNotes {
            let s = q(n.start)
            var len = max(grid, q(n.end) - s)
            if len.isNaN { len = grid }
            onsets[s, default: []].append(n.note)
            lengths[s] = max(lengths[s] ?? 0, len)
        }

        var result: [Slice] = []
        var cursor = 0.0
        for start in onsets.keys.sorted() {
            if start > cursor + 0.001 {
                result.append(Slice(notes: [], startBeats: cursor, lengthBeats: start - cursor))
            }
            let next = onsets.keys.sorted().first { $0 > start } ?? Double.greatestFiniteMagnitude
            let len = min(lengths[start] ?? grid, next - start)
            result.append(Slice(notes: onsets[start]!.sorted(), startBeats: start,
                                lengthBeats: max(grid, len)))
            cursor = start + max(grid, len)
        }
        if cursor < totalBeats - 0.001 {
            result.append(Slice(notes: [], startBeats: cursor, lengthBeats: totalBeats - cursor))
        }
        return result
    }

    private static let durationNames: [(beats: Double, type: String, dots: Int)] = [
        (4.0, "whole", 0), (3.0, "half", 1), (2.0, "half", 0), (1.5, "quarter", 1),
        (1.0, "quarter", 0), (0.75, "eighth", 1), (0.5, "eighth", 0),
        (0.375, "16th", 1), (0.25, "16th", 0),
    ]

    private static func split(_ beats: Double) -> [(Double, String, Int)] {
        var out: [(Double, String, Int)] = []
        var left = beats
        var guardCount = 0
        while left > 0.12 && guardCount < 32 {
            guardCount += 1
            if let d = durationNames.first(where: { $0.beats <= left + 0.001 }) {
                out.append((d.beats, d.type, d.dots)); left -= d.beats
            } else { break }
        }
        if out.isEmpty { out.append((0.25, "16th", 0)) }
        return out
    }

    private static let stepNames = ["C", "C", "D", "E", "E", "F", "F", "G", "A", "A", "B", "B"]
    private static let alters    = [0,   1,   0,  -1,  0,   0,   1,   0,  -1,  0,   -1,  0]

    static func musicXML(take: Take) -> String {
        let tempo = max(30, min(300, take.meta.tempo))
        let divisions = 4                                  // 4 divisions par noire = double croche
        let beatsPerSecond = tempo / 60
        let totalBeats = max(4, ((take.meta.duration * beatsPerSecond) / 4).rounded(.up) * 4)
        let splitAt = 60

        func staffXML(_ upper: Bool, staffNumber: Int) -> [String] {
            let sl = slices(take.notes, tempo: tempo, splitAt: splitAt,
                            upper: upper, totalBeats: totalBeats)
            var perMeasure: [Int: [String]] = [:]

            for s in sl {
                // Une tranche peut franchir une barre de mesure et se découper en
                // plusieurs figures : on les relie alors par des liaisons de tenue.
                var pieces: [(measure: Int, beats: Double, type: String, dots: Int)] = []
                var pos = s.startBeats
                var remaining = s.lengthBeats
                while remaining > 0.12 {
                    let measure = Int(pos / 4)
                    let room = Double(measure + 1) * 4 - pos
                    let chunk = min(remaining, room)
                    for piece in split(chunk) {
                        pieces.append((measure, piece.0, piece.1, piece.2))
                    }
                    pos += chunk
                    remaining -= chunk
                }

                for (k, piece) in pieces.enumerated() {
                    let dur = Int((piece.beats * Double(divisions)).rounded())
                    guard dur > 0 else { continue }
                    let dots = String(repeating: "<dot/>", count: piece.dots)
                    if s.isRest {
                        perMeasure[piece.measure, default: []].append(
                            "      <note><rest/><duration>\(dur)</duration><voice>\(staffNumber)</voice>"
                            + "<type>\(piece.type)</type>\(dots)<staff>\(staffNumber)</staff></note>")
                        continue
                    }
                    let tieToNext = k < pieces.count - 1
                    let tieToPrev = k > 0
                    var tieTags = "", tiedTags = ""
                    if tieToPrev { tieTags += "<tie type=\"stop\"/>"; tiedTags += "<tied type=\"stop\"/>" }
                    if tieToNext { tieTags += "<tie type=\"start\"/>"; tiedTags += "<tied type=\"start\"/>" }
                    let notations = tiedTags.isEmpty ? "" : "<notations>\(tiedTags)</notations>"

                    for (j, n) in s.notes.enumerated() {
                        let pc = n % 12
                        let alter = alters[pc]
                        let octave = n / 12 - 1
                        let chordTag = j > 0 ? "<chord/>" : ""
                        let alterTag = alter != 0 ? "<alter>\(alter)</alter>" : ""
                        // L'altération n'est écrite qu'à la première figure d'une liaison.
                        let accidental = (alter != 0 && !tieToPrev)
                            ? "<accidental>\(alter > 0 ? "sharp" : "flat")</accidental>" : ""
                        perMeasure[piece.measure, default: []].append(
                            "      <note>\(chordTag)<pitch><step>\(stepNames[pc])</step>\(alterTag)"
                            + "<octave>\(octave)</octave></pitch>\(tieTags)<duration>\(dur)</duration>"
                            + "<voice>\(staffNumber)</voice><type>\(piece.type)</type>\(dots)\(accidental)"
                            + "<staff>\(staffNumber)</staff>\(notations)</note>")
                    }
                }
            }

            let count = Int(totalBeats / 4)
            return (0..<count).map { perMeasure[$0]?.joined(separator: "\n") ??
                "      <note><rest measure=\"yes\"/><duration>\(4 * divisions)</duration>"
                + "<voice>\(staffNumber)</voice><staff>\(staffNumber)</staff></note>" }
        }

        let treble = staffXML(true, staffNumber: 1)
        let bass = staffXML(false, staffNumber: 2)
        let measureCount = max(treble.count, bass.count)

        var body = ""
        for m in 0..<measureCount {
            body += "    <measure number=\"\(m + 1)\">\n"
            if m == 0 {
                body += """
                      <attributes>
                        <divisions>\(divisions)</divisions>
                        <key><fifths>0</fifths></key>
                        <time><beats>4</beats><beat-type>4</beat-type></time>
                        <staves>2</staves>
                        <clef number="1"><sign>G</sign><line>2</line></clef>
                        <clef number="2"><sign>F</sign><line>4</line></clef>
                      </attributes>
                      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(Int(tempo))</per-minute></metronome></direction-type><sound tempo="\(Int(tempo))"/></direction>\n
                """
            }
            body += (m < treble.count ? treble[m] : "") + "\n"
            body += "      <backup><duration>\(4 * divisions)</duration></backup>\n"
            body += (m < bass.count ? bass[m] : "") + "\n"
            body += "    </measure>\n"
        }

        let title = take.meta.name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work><work-title>\(title)</work-title></work>
          <identification>
            <encoding><software>Piano Live Setup</software><encoding-date>\(ISO8601DateFormatter().string(from: take.meta.date).prefix(10))</encoding-date></encoding>
          </identification>
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
        \(body)  </part>
        </score-partwise>
        """
    }
}

// MARK: - Grille d'accords

enum ChordTimeline {
    struct Entry: Codable, Hashable, Identifiable {
        var id: String { "\(start)-\(symbol)" }
        var symbol: String
        var quality: String
        var start: Double
        var end: Double
    }

    /// Suit les notes tenues dans le temps et retient les accords qui durent.
    static func build(_ notes: [RecNote], minDuration: Double = 0.28) -> [Entry] {
        guard !notes.isEmpty else { return [] }
        var moments = Set<Double>()
        for n in notes { moments.insert(n.start); moments.insert(n.end) }
        let times = moments.sorted()
        var raw: [(String, String, Double)] = []
        for t in times {
            let held = notes.filter { $0.start <= t + 0.001 && $0.end > t + 0.001 }.map { $0.note }
            guard held.count >= 2 else { raw.append(("—", "", t)); continue }
            let r = ChordDetector.detect(held)
            raw.append((r.symbol, r.quality, t))
        }
        var out: [Entry] = []
        var i = 0
        while i < raw.count {
            let sym = raw[i].0
            var j = i
            while j + 1 < raw.count && raw[j + 1].0 == sym { j += 1 }
            let start = raw[i].2
            let end = j + 1 < raw.count ? raw[j + 1].2 : (notes.map { $0.end }.max() ?? start)
            if sym != "—", end - start >= minDuration {
                out.append(Entry(symbol: sym, quality: raw[i].1, start: start, end: end))
            }
            i = j + 1
        }
        return out
    }

    static func text(_ entries: [Entry], take: TakeMeta) -> String {
        var s = "Grille d'accords — \(take.name)\n"
        s += "Son : \(take.preset) · transposition \(take.transpose >= 0 ? "+" : "")\(take.transpose) · \(Int(take.tempo)) bpm\n"
        s += String(repeating: "—", count: 52) + "\n\n"
        for e in entries {
            let m = Int(e.start) / 60, sec = Int(e.start) % 60
            s += String(format: "%02d:%02d  %-10@  %@\n", m, sec,
                        e.symbol as NSString, e.quality as NSString)
        }
        if entries.isEmpty { s += "(aucun accord tenu détecté)\n" }
        return s
    }
}
