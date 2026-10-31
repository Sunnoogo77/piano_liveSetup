import SwiftUI
import CoreImage.CIFilterBuiltins

// Système de design : palette de studio, sombre et froide, une seule couleur
// d'accent. Les couleurs vives sont réservées à l'information (niveau, alerte),
// jamais à la décoration — c'est ce qui rend un outil lisible sur scène.

enum Tone {
    static let bg0    = Color(red: 0.039, green: 0.047, blue: 0.063)   // fenêtre
    static let bg1    = Color(red: 0.067, green: 0.078, blue: 0.102)   // panneaux
    static let bg2    = Color(red: 0.094, green: 0.108, blue: 0.137)   // éléments surélevés
    static let bg3    = Color(red: 0.129, green: 0.149, blue: 0.188)   // survol / sélection douce

    static let line   = Color.white.opacity(0.07)
    static let line2  = Color.white.opacity(0.12)

    static let txt0   = Color(red: 0.929, green: 0.945, blue: 0.969)
    static let txt1   = Color(red: 0.588, green: 0.631, blue: 0.690)
    static let txt2   = Color(red: 0.361, green: 0.400, blue: 0.463)

    static let accent = Color(red: 0.310, green: 0.820, blue: 0.773)    // sarcelle
    static let accentDim = Color(red: 0.310, green: 0.820, blue: 0.773).opacity(0.18)
    static let blue   = Color(red: 0.478, green: 0.635, blue: 0.969)

    static let ok     = Color(red: 0.329, green: 0.753, blue: 0.478)
    static let warn   = Color(red: 0.878, green: 0.702, blue: 0.255)
    static let hot    = Color(red: 0.878, green: 0.353, blue: 0.306)

    static func category(_ c: Category) -> Color {
        switch c {
        case .acoustic: return Color(red: 0.478, green: 0.635, blue: 0.969)
        case .electric: return Color(red: 0.706, green: 0.557, blue: 0.808)
        case .organ:    return Color(red: 0.514, green: 0.780, blue: 0.651)
        case .pad:      return Color(red: 0.561, green: 0.722, blue: 0.871)
        case .layered:  return Color(red: 0.788, green: 0.651, blue: 0.420)
        case .split:    return Color(red: 0.604, green: 0.643, blue: 0.698)
        }
    }
}

/// Le rendu hors écran ne sait pas dessiner le contenu d'un ScrollView :
/// ce drapeau permet de l'aplatir le temps d'inspecter la mise en page.
enum Flat { static var scrolls = false }

/// ScrollView, sauf en rendu hors écran.
struct Scroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    var showsIndicators = false
    /// Mis à false quand l'aplatissement fausserait la mise en page inspectée.
    var flattenable = true
    @ViewBuilder var content: Content
    var body: some View {
        if Flat.scrolls && flattenable {
            content
        } else {
            ScrollView(axis, showsIndicators: showsIndicators) { content }
        }
    }
}

enum Metric {
    static let radius: CGFloat = 10
    static let radiusL: CGFloat = 14
    static let gap: CGFloat = 14
    static let pad: CGFloat = 16
}

extension Font {
    /// Petite capitale d'étiquette, comme la sérigraphie d'une console.
    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold).width(.condensed)
    }
    static func value(_ size: CGFloat = 13, _ w: Font.Weight = .medium) -> Font {
        .system(size: size, weight: w, design: .rounded).monospacedDigit()
    }
}

/// QR code d'une adresse, pour ouvrir la page sur une tablette sans la taper.
struct QRCode: View {
    let text: String
    var size: CGFloat = 132

    var body: some View {
        if let img = Self.make(text) {
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Tone.bg2).frame(width: size, height: size)
        }
    }

    private static func make(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width,
                                                 height: scaled.extent.height))
    }
}

// MARK: - Composants

/// Étiquette sérigraphiée.
struct Caption: View {
    let text: String
    var color: Color = Tone.txt2
    var body: some View {
        Text(text.uppercased())
            .font(.label()).tracking(1.4)
            .foregroundStyle(color)
    }
}

/// Panneau de base : fond sombre, filet fin, coins arrondis.
struct Panel<Content: View>: View {
    var title: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Caption(text: title) }
                    Spacer(minLength: 8)
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(Metric.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tone.bg1, in: RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous)
            .strokeBorder(Tone.line, lineWidth: 1))
    }
}

/// Bouton de commande : discret au repos, net au survol, franc à l'appui.
struct Key: View {
    let label: String
    var symbol: String? = nil
    var tint: Color = Tone.txt0
    var filled = false
    var wide = false
    var height: CGFloat = 34
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                if !label.isEmpty {
                    Text(label).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }
            .frame(maxWidth: wide ? .infinity : nil)
            .frame(minWidth: wide ? nil : 40, minHeight: height)
            .padding(.horizontal, wide ? 10 : 12)
            .background(filled ? tint.opacity(0.9) : (hover ? Tone.bg3 : Tone.bg2),
                        in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
                .strokeBorder(filled ? .clear : Tone.line2, lineWidth: 1))
            .foregroundStyle(filled ? Tone.bg0 : tint)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Fader dessiné à la main : piste fine, remplissage net, poignée visible.
/// Dessiné plutôt que pris au système, pour rester lisible de loin et cohérent
/// avec le reste de l'outil.
struct Fader: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var format: (Float) -> String = { "\(Int($0 * 100)) %" }
    var tint: Color = Tone.accent
    var enabled = true

    @State private var hover = false

    private var frac: CGFloat {
        CGFloat((value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caption(text: title, color: enabled ? Tone.txt2 : Tone.txt2.opacity(0.45))
                Spacer()
                Text(enabled ? format(value) : "—")
                    .font(.value(11)).foregroundStyle(enabled ? Tone.txt1 : Tone.txt2.opacity(0.55))
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Tone.bg2)
                        .frame(height: 5)
                    Capsule().fill(enabled ? tint.opacity(hover ? 1 : 0.85) : Tone.txt2.opacity(0.3))
                        .frame(width: max(5, w * frac), height: 5)
                    Circle()
                        .fill(enabled ? Tone.txt0 : Tone.txt2.opacity(0.5))
                        .frame(width: hover && enabled ? 13 : 11,
                               height: hover && enabled ? 13 : 11)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: max(0, min(w - 11, w * frac - 5.5)))
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard enabled else { return }
                            let t = Float(max(0, min(1, g.location.x / max(w, 1))))
                            value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 14)
        }
        .onHover { hover = $0 && enabled }
    }
}

/// Bargraph stéréo avec maintien de crête, échelle en dB.
struct LevelMeter: View {
    let left: Float          // dBFS
    let right: Float
    let holdL: Float
    let holdR: Float
    var height: CGFloat = 8

    private func frac(_ db: Float) -> CGFloat {
        CGFloat(max(0, min(1, (db + 54) / 54)))
    }
    private func color(_ db: Float) -> Color {
        db > -1.5 ? Tone.hot : (db > -8 ? Tone.warn : Tone.ok)
    }

    var body: some View {
        VStack(spacing: 3) {
            bar(left, holdL)
            bar(right, holdR)
        }
    }

    private func bar(_ db: Float, _ hold: Float) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tone.bg2)
                Capsule().fill(color(db))
                    .frame(width: geo.size.width * frac(db))
                if hold > -53 {
                    Capsule().fill(color(hold).opacity(0.95))
                        .frame(width: 2)
                        .offset(x: max(0, geo.size.width * frac(hold) - 2))
                }
            }
        }
        .frame(height: height)
    }
}
