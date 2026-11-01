import SwiftUI
import CoreImage.CIFilterBuiltins

// Système de design.
//
// Direction : un rig de piano de scène. Le monde est celui des consoles et des
// claviers : panneaux noirs mats, sérigraphie claire, une seule couleur allumée.
// Le caractère tient en trois mots — posé, exact, chaud sous la main.
//
// Trois règles qui expliquent presque tout le fichier :
//   1. Une seule rampe de gris, froide. Les fonds, les filets et le texte en
//      sortent tous. Rien d'autre n'a de couleur.
//   2. Un seul accent, le sarcelle, et il veut dire « c'est ceci qui est actif ».
//      Les couleurs vives restantes portent une mesure (niveau, alerte), jamais
//      une décoration.
//   3. La hiérarchie vient de la taille et de la couleur, pas de la graisse.
//      Deux graisses suffisent.

enum Tone {
    // Rampe froide. Les quatre fonds sont des marches : chaque élément surélevé
    // monte d'un cran, et la profondeur vient de là — pas d'une ombre portée.
    static let bg0    = Color(red: 0.043, green: 0.051, blue: 0.078)   // fenêtre
    static let bg1    = Color(red: 0.067, green: 0.078, blue: 0.110)   // panneaux
    static let bg2    = Color(red: 0.102, green: 0.118, blue: 0.157)   // éléments surélevés
    static let bg3    = Color(red: 0.141, green: 0.169, blue: 0.220)   // survol / sélection

    static let line   = Color.white.opacity(0.08)
    static let line2  = Color.white.opacity(0.14)

    // Trois rôles de texte, pas davantage. Le troisième reste au-dessus de
    // 4,5:1 sur un panneau : sur scène, la lumière est mauvaise et l'œil est
    // ailleurs.
    static let txt0   = Color(red: 0.933, green: 0.941, blue: 0.961)
    static let txt1   = Color(red: 0.639, green: 0.663, blue: 0.722)
    static let txt2   = Color(red: 0.478, green: 0.510, blue: 0.588)

    static let accent = Color(red: 0.310, green: 0.820, blue: 0.773)    // sarcelle
    static let accentDim = Color(red: 0.310, green: 0.820, blue: 0.773).opacity(0.16)

    // Couleurs qui portent une mesure. Elles n'apparaissent que sur un vumètre,
    // un témoin d'enregistrement ou une alerte.
    static let ok     = Color(red: 0.298, green: 0.765, blue: 0.541)
    static let warn   = Color(red: 0.878, green: 0.702, blue: 0.255)
    static let hot    = Color(red: 0.898, green: 0.282, blue: 0.302)
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

/// Tout tombe sur une grille de 4 points. Un pas de 2 est toléré à l'intérieur
/// d'une petite commande, nulle part ailleurs.
enum Metric {
    static let radius: CGFloat = 10     // commande
    static let radiusL: CGFloat = 14    // panneau
    static let radiusS: CGFloat = 6     // pastille, touche de clavier
    static let gap: CGFloat = 16
    static let pad: CGFloat = 16
    static let row: CGFloat = 32        // hauteur d'une ligne de navigation
}

extension Font {
    /// Étiquette. En casse normale : une console est sérigraphiée en capitales
    /// parce que la peinture le permet, un écran n'a pas cette excuse, et les
    /// capitales espacées se lisent moins vite.
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium)
    }
    /// Toute valeur mesurée — décibels, hertz, demi-tons, pourcentages. En
    /// chasse fixe : les chiffres s'alignent en colonne et ne dansent plus
    /// quand ils changent.
    static func value(_ size: CGFloat = 12, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
    /// Grand nombre affiché : transposition, chronomètre. Famille de
    /// l'interface, chiffres à largeur fixe — ils ne dansent pas quand ils
    /// changent, et le zéro garde sa forme ronde.
    static func display(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font {
        .system(size: size, weight: w).monospacedDigit()
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

/// Étiquette d'un panneau ou d'une commande.
struct Caption: View {
    let text: String
    var color: Color = Tone.txt2
    var body: some View {
        Text(text)
            .font(.label())
            .foregroundStyle(color)
    }
}

/// Panneau de base : fond sombre, filet fin, coins arrondis.
struct Panel<Content: View>: View {
    var title: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

/// Bouton de commande : discret au repos, une marche plus haut au survol,
/// enfoncé de deux points à l'appui. Pas d'autre mouvement.
struct Key: View {
    let label: String
    var symbol: String? = nil
    var tint: Color = Tone.txt0
    var filled = false
    var wide = false
    var height: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                }
                if !label.isEmpty {
                    Text(label).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: wide ? .infinity : nil)
            .frame(minWidth: wide ? nil : 40, minHeight: height)
            .padding(.horizontal, wide ? 12 : 12)
            .background(filled ? tint : (hover ? Tone.bg3 : Tone.bg2),
                        in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
                .strokeBorder(filled ? .clear : Tone.line2, lineWidth: 1))
            .foregroundStyle(filled ? Tone.bg0 : tint)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Fader dessiné à la main : piste fine, remplissage net, poignée visible.
/// Dessiné plutôt que pris au système, pour rester lisible de loin et cohérent
/// avec le reste de l'outil.
struct Fader: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var format: (Float) -> String = { "\(Int(($0 * 100).rounded())) %" }
    var tint: Color = Tone.accent
    var enabled = true

    @State private var hover = false

    private var frac: CGFloat {
        CGFloat((value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .frame(height: 4)
                    Capsule().fill(enabled ? tint.opacity(hover ? 1 : 0.85) : Tone.txt2.opacity(0.3))
                        .frame(width: max(4, w * frac), height: 4)
                    // La poignée se détache par une marche de fond et un filet,
                    // pas par une ombre : sur un fond sombre une ombre ne se voit
                    // pas, elle salit.
                    Circle()
                        .fill(enabled ? Tone.txt0 : Tone.txt2.opacity(0.5))
                        .overlay(Circle().strokeBorder(Tone.bg0.opacity(0.9), lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, min(w - 12, w * frac - 6)))
                }
                .frame(height: 16)
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
            .frame(height: 16)
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
        VStack(spacing: 4) {
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
