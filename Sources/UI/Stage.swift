import SwiftUI
import AppKit

// MARK: - Bibliothèque de sons

struct SidebarView: View {
    @ObservedObject var m: RigModel

    var body: some View {
        VStack(spacing: 0) {
            // Recherche
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Tone.txt2)
                TextField("Rechercher un son", text: $m.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Tone.txt0)
                if !m.search.isEmpty {
                    Button { m.search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Tone.bg2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            // Familles
            Scroll(axis: .horizontal) {
                HStack(spacing: 6) {
                    chip(nil, "Tout")
                    ForEach(Category.allCases, id: \.self) { c in
                        chip(c, c.short)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)

            Divider().overlay(Tone.line)

            Scroll {
                VStack(spacing: 2) {
                    ForEach(groupedCategories, id: \.self) { cat in
                        Section {
                            ForEach(rows(in: cat), id: \.offset) { item in
                                PresetRow(preset: item.element,
                                          isActive: item.offset == m.presetIndex) {
                                    m.select(item.offset)
                                }
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 11, weight: .regular))
                                    .frame(width: 14)
                                Caption(text: cat.rawValue)
                                Spacer()
                            }
                            .foregroundStyle(Tone.txt2)
                            .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 8)
                            .background(Tone.bg1)
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 12)
            }
        }
        .background(Tone.bg1)
    }

    private var groupedCategories: [Category] {
        let present = Set(m.filtered.map { $0.element.category })
        return Category.allCases.filter { present.contains($0) }
    }
    private func rows(in c: Category) -> [(offset: Int, element: Preset)] {
        m.filtered.filter { $0.element.category == c }
    }

    private func chip(_ c: Category?, _ label: String) -> some View {
        let on = m.categoryFilter == c
        return Button { m.categoryFilter = on ? nil : c } label: {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .padding(.horizontal, 12).frame(height: 24)
                .background(on ? Tone.accentDim : Tone.bg2,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(on ? Tone.accent.opacity(0.55) : .clear, lineWidth: 1))
                .foregroundStyle(on ? Tone.accent : Tone.txt1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scène

struct StageView: View {
    @ObservedObject var m: RigModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Metric.gap) {
                header(stageWidth: geo.size.width)
                tabBar
                content(width: geo.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                bottomBar
            }
            .padding(Metric.gap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Tone.bg0)
        }
    }

    // MARK: Onglets

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { t in
                Button { m.tab = t } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.symbol).font(.system(size: 11, weight: .medium))
                        Text(t.rawValue).font(.system(size: 12, weight: .medium))
                        if t == .record && m.isRecording {
                            Circle().fill(Tone.hot).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: Metric.row)
                    .background(m.tab == t ? Tone.bg2 : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(m.tab == t ? Tone.line2 : .clear, lineWidth: 1))
                    .foregroundStyle(m.tab == t ? Tone.accent : Tone.txt1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Tone.bg1, in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            .strokeBorder(Tone.line, lineWidth: 1))
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch m.tab {
        case .play:    PlayScreen(m: m)
        case .eq:      eqScreen(width: width)
        case .chords:  ChordScreen(m: m)
        case .keys:    KeyboardScreen(m: m)
        case .record:  RecordScreen(m: m)
        case .devices: DevicesScreen(m: m)
        }
    }

    // MARK: Écran « Égaliseur »

    private func eqScreen(width: CGFloat) -> some View {
        let wide = width >= 1060
        return VStack(spacing: Metric.gap) {
            AnalyzerView(engine: m.engine, bands: $m.bands, selected: $m.selectedBand) { i, _ in
                m.commitBand(i)
            }
            .frame(minHeight: 170, maxHeight: 430)

            eqStrip(fits: width >= 1130)

            Group {
                if wide {
                    HStack(alignment: .top, spacing: Metric.gap) {
                        pitchPanel.frame(width: 272)
                        levelsPanel.frame(minWidth: 300, maxWidth: 440)
                        effectsPanel.frame(width: 272)
                    }
                    .frame(maxWidth: 1060)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Scroll(axis: .horizontal, flattenable: false) {
                        HStack(alignment: .top, spacing: Metric.gap) {
                            pitchPanel.frame(width: 272)
                            levelsPanel.frame(width: 320)
                            effectsPanel.frame(width: 272)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Bandeau supérieur

    /// Vrai quand l'écran de jeu montre son propre panneau « Hauteur » —
    /// même seuil que `PlayScreen`, à la marge du cadre près.
    private func playShowsPitch(_ stageWidth: CGFloat) -> Bool {
        m.tab == .play && stageWidth - 2 * Metric.gap >= 980
    }

    private func header(stageWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: m.preset.category.symbol)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Tone.txt2)
                    Caption(text: m.preset.category.rawValue)
                }
                Text(m.preset.name)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Tone.txt0)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(m.preset.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Tone.txt1)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if m.chord.symbol != "—" && m.tab != .chords && m.tab != .play {
                VStack(spacing: 1) {
                    Caption(text: "Accord")
                    Text(m.chord.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Tone.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.14), value: m.chord.symbol)
                }
                .frame(minWidth: 70)
            }

            // Transposition, en grand : c'est l'information qu'on cherche du
            // regard. L'onglet Jeu a déjà ses commandes de hauteur avec le même
            // chiffre en grand, alors le bandeau se tait : une valeur affichée
            // deux fois sur un même écran, on finit par ne plus lire ni l'une
            // ni l'autre.
            if !playShowsPitch(stageWidth) {
            VStack(alignment: .trailing, spacing: 4) {
                Caption(text: "Transposition")
                Text(pitchLabel)
                    .font(.display(28))
                    .foregroundStyle(m.transpose == 0 && m.octave == 0 ? Tone.txt0 : Tone.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: m.transpose)
                    .animation(.snappy(duration: 0.15), value: m.octave)
            }
            }

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if m.isRecording {
                        Circle().fill(Tone.hot).frame(width: 6, height: 6)
                        Caption(text: "Enregistre", color: Tone.hot)
                    }
                    Circle().fill(!m.hasKeyboard ? Tone.warn
                                  : (m.midiLive ? Tone.ok : Tone.txt2.opacity(0.4)))
                        .frame(width: 6, height: 6)
                    Caption(text: m.hasKeyboard ? "Clavier" : "Aucun clavier",
                            color: m.hasKeyboard ? Tone.txt2 : Tone.warn)
                    Text(m.held == 1 ? "1 note" : "\(m.held) notes")
                        .font(.value(11)).foregroundStyle(Tone.txt2)
                }
                LevelMeter(left: m.peakDBL, right: m.peakDBR, holdL: m.holdL, holdR: m.holdR)
                    .frame(width: 152)
                HStack(spacing: 0) {
                    ForEach([-48, -30, -18, -9, -3, 0], id: \.self) { t in
                        Text("\(t)").font(.value(10))
                            .foregroundStyle(Tone.txt2)
                            .frame(maxWidth: .infinity, alignment: t == -48 ? .leading : (t == 0 ? .trailing : .center))
                    }
                }
                .frame(width: 152)
                Text(String(format: "crête %+.1f dB", max(m.holdL, m.holdR)))
                    .font(.value(11))
                    .foregroundStyle(max(m.holdL, m.holdR) > -1.5 ? Tone.hot : Tone.txt2)
            }
        }
        .padding(.horizontal, Metric.pad).padding(.vertical, 12)
        .background(Tone.bg1, in: RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusL, style: .continuous)
            .strokeBorder(Tone.line, lineWidth: 1))
    }

    private var pitchLabel: String {
        let total = Int(m.transpose) + Int(m.octave) * 12
        if total == 0 { return "0" }
        return (total > 0 ? "+" : "") + String(total)
    }

    // MARK: Bandes d'égalisation

    @ViewBuilder
    private func eqStrip(fits: Bool) -> some View {
        if fits {
            eqCells.frame(maxWidth: .infinity, alignment: .center).frame(height: 78)
        } else {
            // Fenêtre étroite : un sélecteur de bande et une seule tranche, large.
            // Mieux qu'un défilement horizontal sur une commande qu'on règle à l'oreille.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Caption(text: "Bande")
                    HStack(spacing: 4) {
                        ForEach(m.bands.indices, id: \.self) { i in
                            Button { m.selectedBand = i } label: {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 22, height: 22)
                                    .background(m.selectedBand == i ? Tone.accent :
                                                (m.bands[i].enabled ? Tone.bg2 : Tone.bg1),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(m.selectedBand == i ? .clear : Tone.line, lineWidth: 1))
                                    .foregroundStyle(m.selectedBand == i ? Tone.bg0 :
                                                     (m.bands[i].enabled ? Tone.txt1 : Tone.txt2.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                EQBandCell(index: m.selectedBand, band: $m.bands[m.selectedBand],
                           isSelected: true, onSelect: {},
                           onChange: { m.commitBand(m.selectedBand) })
                    .frame(maxWidth: 240)
                Key(label: "Neutre", symbol: "arrow.counterclockwise", height: 72) { m.resetEQ() }
                Spacer(minLength: 0)
            }
            .frame(height: 78)
        }
    }

    private var eqCells: some View {
        HStack(spacing: 8) {
                ForEach(m.bands.indices, id: \.self) { i in
                    EQBandCell(index: i, band: $m.bands[i],
                               isSelected: m.selectedBand == i,
                               onSelect: { m.selectedBand = i },
                               onChange: { m.commitBand(i) })
                }
                Button { m.resetEQ() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("Neutre").font(.system(size: 11, weight: .medium))
                    }
                    .frame(width: 58, height: 72)
                    .background(Tone.bg1, in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
                        .strokeBorder(Tone.line, lineWidth: 1))
                    .foregroundStyle(Tone.txt1)
                }
                .buttonStyle(.plain)
                .help("Remettre les sept bandes à plat")
        }
    }

    // MARK: Panneaux

    private var pitchPanel: some View {
        Panel(title: "Hauteur") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Key(label: "−1", tint: Tone.txt0, wide: true, height: 38) { m.nudgeTranspose(-1) }
                    Key(label: "0", tint: Tone.accent,
                        filled: m.transpose != 0 || m.octave != 0, wide: true, height: 38) { m.resetPitch() }
                    Key(label: "+1", tint: Tone.txt0, wide: true, height: 38) { m.nudgeTranspose(1) }
                }
                HStack(spacing: 8) {
                    Key(label: "Octave −", symbol: "chevron.down", wide: true) { m.nudgeOctave(-1) }
                    Key(label: "Octave +", symbol: "chevron.up", wide: true) { m.nudgeOctave(1) }
                }
                HStack {
                    Caption(text: "Demi-tons \(m.transpose >= 0 ? "+" : "")\(m.transpose) · Octave \(m.octave >= 0 ? "+" : "")\(m.octave)")
                    Spacer()
                }
            }
        }
    }

    private var levelsPanel: some View {
        Panel(title: "Niveaux") {
            VStack(spacing: 12) {
                Fader(title: "Volume général", value: Binding(get: { m.master }, set: { m.setMaster($0) }))
                Fader(title: m.preset.category == .split ? "Niveau main gauche" : "Niveau de la nappe",
                      value: Binding(get: { m.layerMix }, set: { m.setLayer($0) }),
                      enabled: m.preset.hasSecondLayer)
                HStack(spacing: 8) {
                    Key(label: "Arrêt des notes", symbol: "hand.raised.fill",
                        tint: Tone.hot, wide: true, height: 36) { m.panic() }
                }
            }
        }
    }

    private var effectsPanel: some View {
        Panel(title: "Effets") {
            VStack(spacing: 12) {
                Fader(title: "Saturation", value: Binding(get: { m.drive }, set: { m.setDrive($0) }))
                Fader(title: "Trémolo — profondeur",
                      value: Binding(get: { m.tremDepth }, set: { m.setTrem(rate: m.tremRate > 0.1 ? m.tremRate : 5.2, depth: $0) }))
                Fader(title: "Trémolo — vitesse",
                      value: Binding(get: { m.tremRate }, set: { m.setTrem(rate: $0, depth: m.tremDepth) }),
                      range: 0...12, format: { String(format: "%.1f Hz", $0) },
                      enabled: m.tremDepth > 0.005)
                Fader(title: "Compresseur", value: Binding(get: { m.comp }, set: { m.setComp($0) }))
            }
        }
    }

    // MARK: Barre d'état

    private var bottomBar: some View {
        HStack(spacing: 16) {
            status("speaker.wave.2.fill", m.engine.statusAudio)
            if m.hasKeyboard {
                status("pianokeys", m.engine.midiSourceNames.first ?? "")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "pianokeys").font(.system(size: 11)).foregroundStyle(Tone.warn)
                    Text("aucun clavier détecté — branchez-le, il sera pris tout seul")
                        .font(.system(size: 12)).foregroundStyle(Tone.warn)
                }
            }
            if let note = m.deviceNote {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    Text(note).font(.system(size: 12))
                }
                .foregroundStyle(Tone.ok)
                .transition(.opacity)
            }
            Spacer(minLength: 8)

            Button { m.toggleLocal() } label: {
                HStack(spacing: 6) {
                    Image(systemName: m.localSilenced ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(m.localSilenced ? "Son du piano coupé" : "Son du piano actif")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(m.localSilenced ? Tone.bg2 : Tone.warn.opacity(0.18),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(m.localSilenced ? Tone.line2 : Tone.warn.opacity(0.5), lineWidth: 1))
                .foregroundStyle(m.localSilenced ? Tone.txt1 : Tone.warn)
            }
            .buttonStyle(.plain)
            .help("Coupe ou rétablit le générateur de son interne du clavier (CC 122). Rétabli automatiquement à la fermeture.")
        }
        .padding(.horizontal, Metric.pad).padding(.vertical, 8)
        .background(Tone.bg1, in: RoundedRectangle(cornerRadius: Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            .strokeBorder(Tone.line, lineWidth: 1))
    }

    private func status(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tone.txt2)
            Text(text).font(.system(size: 12)).foregroundStyle(Tone.txt1).lineLimit(1)
        }
    }
}
