import SwiftUI

// Analyseur de spectre temps réel, avec la courbe d'égalisation par-dessus.
// Deux échelles verticales cohabitent, comme sur un égaliseur de studio :
// le niveau du spectre à gauche (−72…0 dBFS), le gain de l'EQ à droite (±18 dB).

private let fMin: Float = 20
private let fMax: Float = 20000
private let eqRange: Float = 18
private let specTop: Float = 0
private let specBottom: Float = -72

@inline(__always) func xForFreq(_ f: Float, _ w: CGFloat) -> CGFloat {
    CGFloat((log10(max(fMin, min(fMax, f))) - log10(fMin)) / (log10(fMax) - log10(fMin))) * w
}
@inline(__always) func freqForX(_ x: CGFloat, _ w: CGFloat) -> Float {
    let t = Float(max(0, min(1, x / max(w, 1))))
    return fMin * pow(fMax / fMin, t)
}
@inline(__always) func yForEQ(_ db: Float, _ h: CGFloat) -> CGFloat {
    h * CGFloat(0.5 - db / (2 * eqRange))
}
@inline(__always) func eqForY(_ y: CGFloat, _ h: CGFloat) -> Float {
    Float(0.5 - y / max(h, 1)) * 2 * eqRange
}
@inline(__always) func yForSpec(_ db: Float, _ h: CGFloat) -> CGFloat {
    h * CGFloat(1 - (max(specBottom, min(specTop, db)) - specBottom) / (specTop - specBottom))
}

struct AnalyzerView: View {
    let engine: LiveEngine
    @Binding var bands: [EQBand]
    @Binding var selected: Int
    var onChange: (Int, EQBand) -> Void

    @State private var dragging: Int? = nil
    private let gridFreqs: [Float] = [30, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { _ in
                    Canvas { ctx, size in
                        draw(ctx: ctx, size: size)
                    }
                }
                handles(w: w, h: h)
            }
            .background(Tone.bg0)
            .clipShape(RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous)
                .strokeBorder(Tone.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
    }

    // MARK: Tracé

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 10, h > 10 else { return }

        // --- grille ---
        for f in gridFreqs {
            let x = xForFreq(f, w)
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            ctx.stroke(p, with: .color(Color.white.opacity(f == 1000 ? 0.09 : 0.05)), lineWidth: 1)
            let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            ctx.draw(Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Tone.txt2),
                     at: CGPoint(x: x + 3, y: h - 9), anchor: .leading)
        }
        for db in stride(from: Float(-12), through: 12, by: 6) {
            let y = yForEQ(db, h)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(p, with: .color(Color.white.opacity(db == 0 ? 0.14 : 0.05)),
                       style: StrokeStyle(lineWidth: 1, dash: db == 0 ? [] : [2, 4]))
            if db != 0 {
                ctx.draw(Text("\(Int(db) > 0 ? "+" : "")\(Int(db))").font(.system(size: 11)).foregroundStyle(Tone.txt2),
                         at: CGPoint(x: w - 5, y: y - 7), anchor: .trailing)
            }
        }

        // --- spectre ---
        let tap = engine.spectrum
        tap.analyse()
        let n = tap.bandCount
        var fill = Path()
        var peakPath = Path()
        fill.move(to: CGPoint(x: 0, y: h))
        for i in 0..<n {
            let f = tap.frequency(forBand: i)
            let x = xForFreq(f, w)
            let y = yForSpec(tap.bandsDB[i], h)
            if i == 0 { fill.addLine(to: CGPoint(x: x, y: y)) } else { fill.addLine(to: CGPoint(x: x, y: y)) }
            let py = yForSpec(tap.peaksDB[i], h)
            if i == 0 { peakPath.move(to: CGPoint(x: x, y: py)) } else { peakPath.addLine(to: CGPoint(x: x, y: py)) }
        }
        fill.addLine(to: CGPoint(x: w, y: h))
        fill.closeSubpath()
        // Remplissage léger qui s'efface vers le bas, puis un trait net sur l'arête :
        // c'est le trait qu'on lit, le remplissage ne fait que donner la masse.
        ctx.fill(fill, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.14), location: 0.0),
                .init(color: Color.white.opacity(0.05), location: 0.35),
                .init(color: Color.white.opacity(0.0), location: 0.8),
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        var edge = Path()
        for i in 0..<n {
            let pt = CGPoint(x: xForFreq(tap.frequency(forBand: i), w),
                             y: yForSpec(tap.bandsDB[i], h))
            if i == 0 { edge.move(to: pt) } else { edge.addLine(to: pt) }
        }
        ctx.stroke(edge, with: .color(Color.white.opacity(0.45)), lineWidth: 1.2)
        ctx.stroke(peakPath, with: .color(Color.white.opacity(0.22)), lineWidth: 1)

        // --- courbe d'égalisation ---
        let steps = 240
        var freqs = [Float](); freqs.reserveCapacity(steps)
        for i in 0..<steps { freqs.append(freqForX(CGFloat(i) / CGFloat(steps - 1) * w, w)) }
        let response = engine.chain.responseDB(freqs: freqs)

        if selected >= 0 && selected < bands.count && bands[selected].enabled {
            let single = engine.chain.bandResponseDB(selected, freqs: freqs)
            var sp = Path()
            for (i, db) in single.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / CGFloat(steps - 1) * w, y: yForEQ(db, h))
                if i == 0 { sp.move(to: pt) } else { sp.addLine(to: pt) }
            }
            ctx.stroke(sp, with: .color(Tone.accent.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }

        var curve = Path()
        for (i, db) in response.enumerated() {
            let pt = CGPoint(x: CGFloat(i) / CGFloat(steps - 1) * w, y: yForEQ(db, h))
            if i == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
        }
        var area = curve
        area.addLine(to: CGPoint(x: w, y: yForEQ(0, h)))
        area.addLine(to: CGPoint(x: 0, y: yForEQ(0, h)))
        area.closeSubpath()
        ctx.fill(area, with: .color(Tone.accent.opacity(0.07)))
        ctx.stroke(curve, with: .color(Tone.accent), lineWidth: 2)
    }

    // MARK: Points de bande

    private func handles(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(bands.indices, id: \.self) { i in
                let b = bands[i]
                let pos = CGPoint(x: xForFreq(b.freq, w),
                                  y: yForEQ(b.kind.usesGain ? b.gain : 0, h))
                ZStack {
                    Circle()
                        .fill(b.enabled ? Tone.accent.opacity(selected == i ? 0.95 : 0.55)
                                        : Tone.txt2.opacity(0.4))
                        .frame(width: selected == i ? 16 : 12, height: selected == i ? 16 : 12)
                    Circle().strokeBorder(Tone.bg0.opacity(0.8), lineWidth: 1.5)
                        .frame(width: selected == i ? 16 : 12, height: selected == i ? 16 : 12)
                    Text("\(i + 1)")
                        .font(.value(10))
                        .foregroundStyle(Tone.bg0)
                        .opacity(selected == i ? 1 : 0)
                }
                .position(pos)
                .animation(.easeOut(duration: 0.12), value: selected)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragging == nil {
                        // On attrape le point le plus proche du doigt.
                        var best = 0
                        var bestD = CGFloat.greatestFiniteMagnitude
                        for i in bands.indices {
                            let p = CGPoint(x: xForFreq(bands[i].freq, w),
                                            y: yForEQ(bands[i].kind.usesGain ? bands[i].gain : 0, h))
                            let d = hypot(p.x - g.startLocation.x, p.y - g.startLocation.y)
                            if d < bestD { bestD = d; best = i }
                        }
                        guard bestD < 44 else { return }
                        dragging = best
                        selected = best
                    }
                    guard let i = dragging else { return }
                    var b = bands[i]
                    b.freq = freqForX(g.location.x, w)
                    if b.kind.usesGain {
                        b.gain = max(-eqRange, min(eqRange, eqForY(g.location.y, h)))
                    }
                    b.enabled = true
                    bands[i] = b
                    onChange(i, b)
                }
                .onEnded { _ in dragging = nil }
        )
    }
}
