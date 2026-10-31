import SwiftUI

// MARK: - Clavier 88 touches

struct KeyboardView: View {
    let active: Set<Int>
    var splitAt: Int = 60
    var showNames = true
    var lowest = 21, highest = 108          // La0 → Do8

    private func isWhite(_ n: Int) -> Bool {
        [0, 2, 4, 5, 7, 9, 11].contains(((n % 12) + 12) % 12)
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let whites = (lowest...highest).filter(isWhite)
                let ww = size.width / CGFloat(whites.count)
                let wh = size.height
                let bw = ww * 0.62
                let bh = wh * 0.62

                var xFor: [Int: CGFloat] = [:]
                for (i, n) in whites.enumerated() { xFor[n] = CGFloat(i) * ww }

                // touches blanches
                for n in whites {
                    let x = xFor[n]!
                    let rect = CGRect(x: x + 0.5, y: 0, width: ww - 1, height: wh)
                    let on = active.contains(n)
                    let tint = n < splitAt ? Tone.blue : Tone.accent
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(on ? tint : Color(white: 0.90)))
                    if on {
                        ctx.fill(Path(roundedRect: CGRect(x: rect.minX, y: rect.maxY - wh * 0.22,
                                                          width: rect.width, height: wh * 0.22),
                                      cornerRadius: 2),
                                 with: .color(tint.opacity(0.65)))
                    }
                    if showNames, n % 12 == 0, ww > 11 {
                        ctx.draw(Text("Do\(n / 12 - 1)")
                                    .font(.system(size: min(9, ww * 0.42), weight: .semibold))
                                    .foregroundStyle(on ? Color.white.opacity(0.9) : Color(white: 0.45)),
                                 at: CGPoint(x: rect.midX, y: wh - 9), anchor: .center)
                    }
                }

                // touches noires, par-dessus
                for n in lowest...highest where !isWhite(n) {
                    guard let prev = xFor[n - 1] else { continue }
                    let rect = CGRect(x: prev + ww - bw / 2, y: 0, width: bw, height: bh)
                    let on = active.contains(n)
                    let tint = n < splitAt ? Tone.blue : Tone.accent
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(on ? tint.opacity(0.92) : Color(white: 0.11)))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 2),
                               with: .color(Color.black.opacity(0.65)), lineWidth: 0.8)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Tone.line2, lineWidth: 1))
    }
}

// MARK: - Affichage d'accord

struct ChordBadge: View {
    let chord: ChordResult
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 8) {
            Caption(text: "Accord détecté")
            Text(chord.symbol)
                .font(.system(size: compact ? 40 : 86, weight: .semibold, design: .rounded))
                .foregroundStyle(chord.symbol == "—" ? Tone.txt2 : Tone.accent)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.14), value: chord.symbol)
                .lineLimit(1).minimumScaleFactor(0.5)
            if !chord.quality.isEmpty {
                Text(chord.quality)
                    .font(.system(size: compact ? 11 : 14))
                    .foregroundStyle(Tone.txt1)
            }
            if !chord.noteNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(chord.noteNames.enumerated()), id: \.offset) { i, n in
                        VStack(spacing: 1) {
                            Text(n).font(.system(size: compact ? 11 : 13, weight: .medium))
                                .foregroundStyle(Tone.txt0)
                            if i < chord.degrees.count {
                                Text(chord.degrees[i]).font(.system(size: 9))
                                    .foregroundStyle(Tone.txt2)
                            }
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Tone.bg2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Écran « Jeu »

struct PlayScreen: View {
    @ObservedObject var m: RigModel

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 980
            VStack(spacing: Metric.gap) {
                HStack(alignment: .top, spacing: Metric.gap) {
                    Panel {
                        ChordBadge(chord: m.chord)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if wide {
                        Panel(title: "Hauteur") {
                            VStack(spacing: 10) {
                                Text(pitchLabel)
                                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(m.transpose == 0 && m.octave == 0 ? Tone.txt0 : Tone.accent)
                                    .frame(maxWidth: .infinity)
                                HStack(spacing: 7) {
                                    Key(label: "−1", wide: true, height: 40) { m.nudgeTranspose(-1) }
                                    Key(label: "0", tint: Tone.accent,
                                        filled: m.transpose != 0 || m.octave != 0, wide: true, height: 40) { m.resetPitch() }
                                    Key(label: "+1", wide: true, height: 40) { m.nudgeTranspose(1) }
                                }
                                HStack(spacing: 7) {
                                    Key(label: "Octave −", symbol: "chevron.down", wide: true) { m.nudgeOctave(-1) }
                                    Key(label: "Octave +", symbol: "chevron.up", wide: true) { m.nudgeOctave(1) }
                                }
                            }
                        }
                        .frame(width: 300)
                    }
                }

                KeyboardView(active: Set(m.sounding), splitAt: splitPoint)
                    .frame(height: 92)

                HStack(alignment: .top, spacing: Metric.gap) {
                    Panel(title: "Niveaux") {
                        VStack(spacing: 12) {
                            Fader(title: "Volume général",
                                  value: Binding(get: { m.master }, set: { m.setMaster($0) }))
                            Fader(title: m.preset.category == .split ? "Niveau main gauche" : "Niveau de la nappe",
                                  value: Binding(get: { m.layerMix }, set: { m.setLayer($0) }),
                                  tint: Tone.category(m.preset.category),
                                  enabled: m.preset.hasSecondLayer)
                        }
                    }
                    Panel(title: "Scène") {
                        HStack(spacing: 8) {
                            Key(label: "Arrêt des notes", symbol: "hand.raised.fill",
                                tint: Tone.hot, wide: true, height: 40) { m.panic() }
                            Key(label: m.isRecording ? "Arrêter" : "Enregistrer",
                                symbol: m.isRecording ? "stop.fill" : "record.circle",
                                tint: m.isRecording ? Tone.hot : Tone.txt0,
                                filled: m.isRecording, wide: true, height: 40) { m.toggleRecording() }
                        }
                    }
                    .frame(width: wide ? 320 : 260)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var splitPoint: Int {
        if m.preset.category == .split, m.preset.layers.count > 1 {
            return Int(m.preset.layers[1].loKey)
        }
        return 60
    }
    private var pitchLabel: String {
        let t = Int(m.transpose) + Int(m.octave) * 12
        return t == 0 ? "0" : (t > 0 ? "+\(t)" : "\(t)")
    }
}

// MARK: - Écran « Accords »

struct ChordScreen: View {
    @ObservedObject var m: RigModel

    var body: some View {
        VStack(spacing: Metric.gap) {
            Panel {
                HStack(alignment: .top, spacing: 24) {
                    ChordBadge(chord: m.chord)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Caption(text: "Fiabilité")
                        Text("\(Int(m.chord.confidence * 100)) %")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(m.chord.confidence > 0.8 ? Tone.ok :
                                             (m.chord.confidence > 0.5 ? Tone.warn : Tone.txt2))
                        if m.chord.isInversion {
                            Text("renversement").font(.system(size: 10))
                                .foregroundStyle(Tone.txt2)
                        }
                        if Int(m.transpose) + Int(m.octave) * 12 != 0 {
                            Text("hauteur transposée")
                                .font(.system(size: 10)).foregroundStyle(Tone.warn)
                        }
                    }
                }
            }

            KeyboardView(active: Set(m.sounding), splitAt: 60)
                .frame(height: 104)

            Panel(title: "Accords joués") {
                if m.chordHistory.isEmpty {
                    Text("Jouez trois notes ou plus : les accords tenus s'inscrivent ici.")
                        .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
                } else {
                    Scroll {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(Array(m.chordHistory.enumerated()), id: \.offset) { i, c in
                                VStack(spacing: 2) {
                                    Text(c.symbol)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(i == 0 ? Tone.accent : Tone.txt0)
                                    Text(c.quality).font(.system(size: 9))
                                        .foregroundStyle(Tone.txt2).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(i == 0 ? Tone.accentDim : Tone.bg2,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Écran « Clavier »

struct KeyboardScreen: View {
    @ObservedObject var m: RigModel

    var body: some View {
        VStack(spacing: Metric.gap) {
            Panel {
                VStack(spacing: 14) {
                    KeyboardView(active: Set(m.sounding), splitAt: splitPoint)
                        .frame(minHeight: 150, maxHeight: 260)
                    HStack(spacing: 18) {
                        legend(Tone.blue, m.preset.category == .split ? "Main gauche" : "Sous Do4")
                        legend(Tone.accent, m.preset.category == .split ? "Main droite" : "Do4 et au-dessus")
                        Spacer()
                        Text("\(m.sounding.count) note\(m.sounding.count == 1 ? "" : "s") tenue\(m.sounding.count == 1 ? "" : "s")")
                            .font(.value(11)).foregroundStyle(Tone.txt1)
                    }
                }
            }
            HStack(alignment: .top, spacing: Metric.gap) {
                Panel { ChordBadge(chord: m.chord, compact: true) }
                Panel(title: "Notes") {
                    if m.sounding.isEmpty {
                        Text("—").font(.value(16)).foregroundStyle(Tone.txt2)
                    } else {
                        Text(m.sounding.map { Note.fullName($0, flat: false) }.joined(separator: "   "))
                            .font(.value(14)).foregroundStyle(Tone.txt0)
                    }
                }
                .frame(width: 300)
            }
            Spacer(minLength: 0)
        }
    }

    private var splitPoint: Int {
        if m.preset.category == .split, m.preset.layers.count > 1 {
            return Int(m.preset.layers[1].loKey)
        }
        return 60
    }
    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 14, height: 8)
            Text(t).font(.system(size: 10.5)).foregroundStyle(Tone.txt2)
        }
    }
}
