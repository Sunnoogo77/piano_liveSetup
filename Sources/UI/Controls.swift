import SwiftUI

/// Valeur réglée en tirant verticalement, comme sur un plug-in de studio :
/// compact, précis, et sans curseur qui s'étire sur toute la largeur.
struct NumberDrag: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var sensitivity: Float = 1
    var logarithmic = false
    var format: (Float) -> String
    var enabled = true
    var tint: Color = Tone.accent
    var onCommit: () -> Void = {}

    @State private var startValue: Float? = nil
    @State private var hover = false

    var body: some View {
        VStack(spacing: 2) {
            Caption(text: title, color: enabled ? Tone.txt2 : Tone.txt2.opacity(0.45))
            Text(format(value))
                .font(.value(12, .semibold))
                .foregroundStyle(enabled ? (hover ? tint : Tone.txt0) : Tone.txt2.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(hover && enabled ? Tone.bg3 : Tone.bg2,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Tone.line, lineWidth: 1))
        }
        .opacity(enabled ? 1 : 0.55)
        .onHover { hover = $0 && enabled }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { g in
                    guard enabled else { return }
                    if startValue == nil { startValue = value }
                    guard let s = startValue else { return }
                    let delta = Float(-g.translation.height) * 0.01 * sensitivity
                    if logarithmic {
                        let lo = log10(range.lowerBound), hi = log10(range.upperBound)
                        let cur = (log10(s) - lo) / (hi - lo)
                        let next = max(0, min(1, cur + delta))
                        value = pow(10, lo + next * (hi - lo))
                    } else {
                        let span = range.upperBound - range.lowerBound
                        value = max(range.lowerBound, min(range.upperBound, s + delta * span))
                    }
                    onCommit()
                }
                .onEnded { _ in startValue = nil; onCommit() }
        )
    }
}

/// Tranche d'une bande d'égalisation : en-tête, puis fréquence, gain et Q
/// alignés horizontalement — compact, comme une tranche de console.
struct EQBandCell: View {
    let index: Int
    @Binding var band: EQBand
    let isSelected: Bool
    let onSelect: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(isSelected ? Tone.bg0 : Tone.txt2)
                    .frame(width: 15, height: 15)
                    .background(isSelected ? Tone.accent : Tone.bg3, in: Circle())
                Caption(text: band.label, color: isSelected ? Tone.accent : Tone.txt2)
                Spacer(minLength: 2)
                Button {
                    band.enabled.toggle(); onChange()
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(band.enabled ? Tone.ok : Tone.txt2.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(band.enabled ? "Désactiver cette bande" : "Activer cette bande")
            }

            HStack(spacing: 5) {
                NumberDrag(title: "Fréq", value: $band.freq, range: 20...20000,
                           sensitivity: 2, logarithmic: true,
                           format: { $0 >= 1000 ? String(format: "%.1fk", $0 / 1000) : String(format: "%.0f", $0) },
                           enabled: band.enabled, onCommit: onChange)
                NumberDrag(title: "Gain", value: $band.gain, range: -18...18,
                           sensitivity: 2.4,
                           format: { String(format: "%+.1f", $0) },
                           enabled: band.enabled && band.kind.usesGain, onCommit: onChange)
                NumberDrag(title: band.kind.usesGain ? "Q" : "Pente", value: $band.q, range: 0.2...8,
                           sensitivity: 1.6, logarithmic: true,
                           format: { String(format: "%.2f", $0) },
                           enabled: band.enabled, onCommit: onChange)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .frame(minWidth: 132, idealWidth: 140, maxWidth: 240)
        .background(isSelected ? Tone.bg2 : Tone.bg1,
                    in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            .strokeBorder(isSelected ? Tone.accent.opacity(0.55) : Tone.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Ligne de la bibliothèque de sons.
struct PresetRow: View {
    let preset: Preset
    let isActive: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Tone.category(preset.category))
                    .frame(width: 3, height: 26)
                    .opacity(isActive ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Tone.txt0 : Tone.txt1)
                        .lineLimit(1)
                    Text(preset.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Tone.txt2)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if preset.hasSecondLayer {
                    Image(systemName: preset.category == .split ? "rectangle.split.2x1" : "square.stack.3d.up")
                        .font(.system(size: 9))
                        .foregroundStyle(Tone.txt2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Tone.accentDim : (hover ? Tone.bg2 : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
