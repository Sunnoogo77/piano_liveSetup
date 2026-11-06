import SwiftUI
import AppKit

// MARK: - Écran « Enregistrer »

struct RecordScreen: View {
    @ObservedObject var m: RigModel
    var width: CGFloat = 1200

    var body: some View {
        VStack(spacing: Metric.gap) {
            recorder
            if width >= 940 {
                HStack(alignment: .top, spacing: Metric.gap) {
                    producedPanel.frame(width: 300)
                    takesPanel
                }
                .frame(maxHeight: .infinity)
            } else {
                producedPanel
                takesPanel.frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Le bouton et le chronomètre

    private var recorder: some View {
        Panel {
            HStack(alignment: .center, spacing: 20) {
                Button { m.toggleRecording() } label: {
                    ZStack {
                        Circle()
                            .fill(m.isRecording ? Tone.hot : Tone.bg2)
                            .frame(width: 60, height: 60)
                        Circle().strokeBorder(m.isRecording ? Tone.hot.opacity(0.4) : Tone.line2,
                                              lineWidth: 2).frame(width: 70, height: 70)
                        Image(systemName: m.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: m.isRecording ? 22 : 28, weight: .medium))
                            .foregroundStyle(m.isRecording ? .white : Tone.hot)
                    }
                }
                .buttonStyle(.plain)
                .help(m.isRecording ? "Arrêter la prise" : "Lancer une prise")

                VStack(alignment: .leading, spacing: 4) {
                    Caption(text: m.isRecording ? "Enregistrement en cours" : "Prêt à enregistrer",
                            color: m.isRecording ? Tone.hot : Tone.txt2)
                    Text(timeLabel)
                        .font(.display(34))
                        .foregroundStyle(m.isRecording ? Tone.txt0 : Tone.txt2)
                    Text(m.isRecording
                         ? "\(m.recNotes) note\(m.recNotes == 1 ? "" : "s") · \(m.preset.name)"
                         : "Le son actif et la transposition partent avec la prise")
                        .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                }
                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $m.recordAudio) {
                        Text("Enregistrer aussi l'audio")
                            .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                    }
                    .toggleStyle(.switch).tint(Tone.accent).disabled(m.isRecording)
                    .help("WAV 24 bits stéréo : le son exact qui sort, effets compris.")
                    HStack(spacing: 8) {
                        Caption(text: "Tempo de la partition")
                        Spacer(minLength: 8)
                        Text("\(Int(m.tempo)) bpm").font(.value(11)).foregroundStyle(Tone.txt1)
                    }
                    Slider(value: $m.tempo, in: 40...200, step: 1)
                        .controlSize(.small).tint(Tone.accent).disabled(m.isRecording)
                }
                .frame(width: 260)
            }
        }
    }

    // MARK: Les quatre fichiers

    /// En colonne plutôt qu'en rangée : quatre cases étirées côte à côte sur
    /// toute la largeur, c'est surtout du vide entre quatre noms de fichiers.
    private var producedPanel: some View {
        Panel(title: "Ce que donne une prise") {
            VStack(alignment: .leading, spacing: 8) {
                produced("waveform", "audio.wav", "Le son exact qui sort, 24 bits")
                produced("pianokeys", "performance.mid", "Rejouable sur le piano, timing exact")
                produced("doc.richtext", "partition.musicxml", "Partition quantifiée, deux portées")
                produced("music.quarternote.3", "accords.txt", "Grille d'accords horodatée")
            }
        }
    }

    private var takesPanel: some View {
        Panel(title: "Prises enregistrées", trailing: AnyView(
            Button { m.refreshTakes() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    .foregroundStyle(Tone.txt2)
            }.buttonStyle(.plain).help("Relire le dossier des prises"))) {
            if m.takes.isEmpty {
                Text("Aucune prise pour l'instant.")
                    .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Scroll {
                    VStack(spacing: 6) {
                        ForEach(m.takes) { t in takeRow(t) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var timeLabel: String {
        let s = Int(m.recSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func produced(_ symbol: String, _ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tone.txt2)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.value(11, .medium)).foregroundStyle(Tone.txt0)
                Text(desc).font(.system(size: 11)).foregroundStyle(Tone.txt2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func takeRow(_ t: TakeMeta) -> some View {
        let dir = TakeStore.folder(t.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tone.txt0).lineLimit(1)
                Text("\(dateLabel(t.date)) · \(String(format: "%.0f", t.duration)) s · \(t.noteCount) notes · \(t.preset)"
                     + (t.transpose != 0 ? " · transposé \(t.transpose > 0 ? "+" : "")\(t.transpose)" : ""))
                    .font(.system(size: 11)).foregroundStyle(Tone.txt2).lineLimit(1)
            }
            Spacer(minLength: 6)
            if t.hasAudio {
                fileButton("waveform", "Écouter le WAV") { m.openFile(dir.appendingPathComponent("audio.wav")) }
            }
            fileButton("pianokeys", "Ouvrir le MIDI") { m.openFile(dir.appendingPathComponent("performance.mid")) }
            fileButton("doc.richtext", "Ouvrir la partition") { m.openFile(dir.appendingPathComponent("partition.musicxml")) }
            fileButton("music.quarternote.3", "Voir la grille d'accords") { m.openFile(dir.appendingPathComponent("accords.txt")) }
            fileButton("folder", "Révéler dans le Finder") { m.revealTake(t.id) }
            fileButton("trash", "Supprimer", tint: Tone.hot) { m.deleteTake(t.id) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Tone.bg2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM 'à' HH'h'mm"
        return f.string(from: d)
    }

    private func fileButton(_ symbol: String, _ help: String,
                            tint: Color = Tone.txt1, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .frame(width: 26, height: 24)
                .background(Tone.bg3, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain).help(help)
    }
}

// MARK: - Écran « Périphériques »

/// Un écran de réglages, pas un tableau de bord : les panneaux font la largeur
/// dont ils ont besoin et se rangent en colonnes. Sur un grand écran, la
/// colonne s'arrête — une case de réglages étirée sur 1700 points, c'est du
/// vide avec une case autour.
struct DevicesScreen: View {
    @ObservedObject var m: RigModel
    var width: CGFloat = 1200

    private var columns: Int { width >= 1180 ? 3 : (width >= 820 ? 2 : 1) }

    var body: some View {
        Scroll {
            VStack(spacing: Metric.gap) {
                settings
                micPanel
                versionPanel
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var settings: some View {
        switch columns {
        case 3:
            HStack(alignment: .top, spacing: Metric.gap) {
                keyboardPanel; outputPanel; remotePanel
            }
        case 2:
            // Deux colonnes, pas deux rangées : un panneau seul sur sa rangée
            // s'étire sur toute la largeur et devient une case à moitié vide.
            HStack(alignment: .top, spacing: Metric.gap) {
                VStack(spacing: Metric.gap) { keyboardPanel; outputPanel }
                remotePanel
            }
        default:
            VStack(spacing: Metric.gap) { keyboardPanel; outputPanel; remotePanel }
        }
    }

    // MARK: Clavier

    private var keyboardPanel: some View {
        Panel(title: "Clavier MIDI") {
            VStack(alignment: .leading, spacing: 8) {
                if m.engine.midiSourceNames.isEmpty {
                    row("exclamationmark.triangle", "Aucun clavier détecté", Tone.warn)
                    note("Branchez le piano en USB et allumez-le : il est pris tout seul, son interne coupé, sortie basculée dessus s'il sait la recevoir.")
                } else {
                    ForEach(m.engine.midiSourceNames, id: \.self) { n in
                        row("pianokeys", n, Tone.ok)
                    }
                    row("arrow.up.right", "Retour vers : \(m.engine.midiDestinationName)", Tone.txt1)
                }
                Divider().overlay(Tone.line)
                Toggle(isOn: Binding(get: { m.localSilenced }, set: { _ in m.toggleLocal() })) {
                    Text("Couper le son interne du clavier")
                        .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                }
                .toggleStyle(.switch).tint(Tone.accent)
                .help("Message MIDI standard (CC 122). Rétabli à la fermeture, et de toute façon oublié par l'instrument à l'extinction.")
                if m.localSilenced && !m.engine.midiSourceNames.isEmpty {
                    // Le MIDI ne va que dans un sens ici : l'instrument n'accuse
                    // pas réception, et tous ne reçoivent pas ce message. Dire
                    // « coupé » serait une promesse que rien ne vérifie.
                    note("Message envoyé — l'instrument ne répond pas pour dire s'il l'a suivi. S'il continue de jouer son propre son, cherchez « Local Control » dans ses réglages et mettez-le sur Off.")
                }
                if let err = m.engine.midiClientError {
                    Text(err).font(.system(size: 12)).foregroundStyle(Tone.hot)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    note(hotPlugLabel)
                }
                Key(label: "Rechercher les appareils", symbol: "arrow.clockwise", wide: true) {
                    m.engine.rescanMIDI(); m.refreshDevices()
                }
            }
        }
    }

    private var hotPlugLabel: String {
        switch m.engine.midiNotifications {
        case 0:  return "Détection à chaud active — aucun changement vu."
        case 1:  return "Détection à chaud active — un changement vu."
        default: return "Détection à chaud active — \(m.engine.midiNotifications) changements vus."
        }
    }

    // MARK: Sortie

    private var outputPanel: some View {
        Panel(title: "Sortie audio") {
            VStack(alignment: .leading, spacing: 8) {
                Text(m.engine.statusAudio)
                    .font(.value(11)).foregroundStyle(Tone.txt1)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Tone.line)
                ForEach(m.audioDevices, id: \.self) { d in
                    let on = m.engine.audioDeviceLabel == d
                    Button { m.chooseAudioDevice(d) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(on ? Tone.accent : Tone.txt2)
                            Text(d).font(.system(size: 12))
                                .foregroundStyle(on ? Tone.txt0 : Tone.txt1)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(Tone.line)
                Toggle(isOn: Binding(get: { m.followOutput }, set: { m.setFollowOutput($0) })) {
                    Text("Suivre le clavier automatiquement")
                        .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                }
                .toggleStyle(.switch).tint(Tone.accent)
                .help("Beaucoup de pianos numériques renvoient le son du Mac dans leurs haut-parleurs par le câble USB. Quand c'est le cas et que cette option est active, la sortie bascule dessus dès que l'instrument est allumé.")
                note("Décochez pour imposer votre choix — un micro virtuel pour Teams ou Zoom, par exemple.")
            }
        }
    }

    // MARK: Page de commande

    private var remotePanel: some View {
        Panel(title: "Contrôle à distance") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { m.remoteOn }, set: { _ in m.toggleRemote() })) {
                        Text("Publier une page de commande")
                            .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                    }
                    .toggleStyle(.switch).tint(Tone.accent)
                    Spacer(minLength: 0)
                    if m.remoteOn {
                        Circle().fill(Tone.ok).frame(width: 6, height: 6)
                        Caption(text: m.remoteClients == 1 ? "1 appareil" : "\(m.remoteClients) appareils",
                                color: Tone.ok)
                    }
                }

                if m.remoteOn {
                    VStack(alignment: .leading, spacing: 4) {
                        Caption(text: "Clé d'accès")
                        Text(m.remoteKey)
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .tracking(3).foregroundStyle(Tone.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Caption(text: "Adresses à ouvrir")
                        ForEach(m.remoteAddresses, id: \.self) { a in
                            Button { copy(a) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                                    Text(a).font(.value(11))
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                .foregroundStyle(Tone.txt1)
                            }
                            .buttonStyle(.plain)
                            .help("Copier l'adresse")
                        }
                    }
                    if let first = m.remoteAddresses.first {
                        HStack(spacing: 12) {
                            QRCode(text: first, size: 108)
                            note("Scannez le code sur la tablette. Le Mac continue de faire le son ; l'appareil ne sert que de commande.")
                        }
                    }
                } else {
                    note("Sons, transposition, niveaux, égaliseur, arrêt des notes et enregistrement, depuis n'importe quel navigateur du réseau. Rien à installer sur la tablette.")
                }
                if let msg = m.remoteMessage {
                    Text(msg).font(.system(size: 12)).foregroundStyle(Tone.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Micro

    /// Le micro a droit au même analyseur que le piano : on règle une voix en
    /// regardant où elle est, pas en déplaçant sept curseurs à l'aveugle.
    private var micPanel: some View {
        Panel(title: "Entrée micro", trailing: AnyView(
            HStack(spacing: 8) {
                Image(systemName: m.micAuth == .authorized
                      ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(m.micAuth == .authorized ? Tone.ok : Tone.warn)
                Caption(text: "Autorisation macOS : \(m.micAuth.human)",
                        color: m.micAuth == .authorized ? Tone.txt2 : Tone.warn)
            })) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("", selection: $m.micDeviceID) {
                        ForEach(m.micDevices, id: \.id) { d in Text(d.name).tag(d.id) }
                    }
                    .labelsHidden().frame(width: 240).disabled(m.micOn)
                    Key(label: m.micOn ? "Arrêter l'entrée" : "Activer l'entrée",
                        symbol: m.micOn ? "mic.slash.fill" : "mic.fill",
                        tint: m.micOn ? Tone.hot : Tone.txt0) { m.toggleMic() }
                    Toggle(isOn: Binding(get: { m.micMonitoring },
                                         set: { m.setMicMonitoring($0) })) {
                        Text("Envoyer dans la sortie")
                            .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                    }
                    .toggleStyle(.switch).tint(Tone.warn).disabled(!m.micOn)
                    Spacer(minLength: 8)
                    Caption(text: "Entrée")
                    LevelMeter(left: m.micPeakDB, right: m.micPeakDB,
                               holdL: m.micPeakDB, holdR: m.micPeakDB, height: 6)
                        .frame(width: 120)
                }

                if m.micAuth == .denied || m.micAuth == .restricted {
                    HStack(spacing: 8) {
                        Key(label: "Ouvrir les réglages", symbol: "gear") { m.openMicSettings() }
                        Key(label: "Revérifier", symbol: "arrow.clockwise") { m.refreshMicAuth() }
                        Key(label: "Chercher les entrées", symbol: "arrow.clockwise") { m.refreshDevices() }
                        Spacer(minLength: 0)
                    }
                }

                ZStack {
                    AnalyzerView(tap: m.engine.mic.spectrum, chain: m.engine.mic.chain,
                                 bands: $m.micBands, selected: $m.micSelectedBand) { _, _ in
                        m.commitMicBands()
                    }
                    if !m.micOn {
                        Text("Ouvrez l'entrée pour voir ce que le micro entend.")
                            .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(height: 188)

                micBandStrip

                HStack(spacing: Metric.gap) {
                    Fader(title: "Gain du micro",
                          value: Binding(get: { m.micGain }, set: { m.setMicGain($0) }),
                          range: 0...3, format: { String(format: "%+.1f dB", 20 * log10(max(0.001, $0))) })
                        .frame(maxWidth: 260)
                    Fader(title: "Compresseur voix",
                          value: Binding(get: { m.micComp }, set: { m.setMicComp($0) }))
                        .frame(maxWidth: 260)
                    Spacer(minLength: 0)
                }

                if m.micOn && !m.micMonitoring {
                    note("L'entrée est ouverte, l'écoute est coupée : la courbe bouge, rien ne sort.")
                } else if m.micMonitoring {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Tone.warn)
                        Text("Micro renvoyé dans les haut-parleurs : risque de larsen.")
                            .font(.system(size: 12)).foregroundStyle(Tone.warn)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Tone.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                if let msg = m.micMessage {
                    Text(msg).font(.system(size: 12))
                        .foregroundStyle(m.micSilent ? Tone.warn : Tone.hot)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Les sept tranches tiennent côte à côte dès qu'il y a la place ; en
    /// dessous, elles défilent plutôt que de se tasser.
    @ViewBuilder
    private var micBandStrip: some View {
        let cells = ForEach(m.micBands.indices, id: \.self) { i in
            EQBandCell(index: i, band: $m.micBands[i],
                       isSelected: m.micSelectedBand == i,
                       onSelect: { m.micSelectedBand = i },
                       onChange: { m.commitMicBands() })
        }
        if width >= 1180 {
            HStack(spacing: 8) {
                cells
                Key(label: "Réglage de départ", symbol: "arrow.counterclockwise", height: 72) {
                    m.resetMicEQ()
                }
            }
            .frame(height: 78)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Scroll(axis: .horizontal, flattenable: false) {
                    HStack(spacing: 8) { cells }
                }
                .frame(height: 78)
                Key(label: "Réglage de départ", symbol: "arrow.counterclockwise", height: 28) {
                    m.resetMicEQ()
                }
            }
        }
    }

    // MARK: Version

    private var versionPanel: some View {
        Panel(title: "Version et mises à jour") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(AppInfo.version)
                        .font(.display(18)).foregroundStyle(Tone.txt0)
                    Text("\(AppInfo.commit) · \(AppInfo.built)")
                        .font(.value(11)).foregroundStyle(Tone.txt2)
                    Spacer(minLength: 8)
                    Toggle(isOn: Binding(get: { m.engine.config.checkUpdates },
                                         set: { m.setCheckUpdates($0) })) {
                        Text("Regarder au lancement")
                            .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                    }
                    .toggleStyle(.switch).tint(Tone.accent)
                    .help("Seul le numéro de version est demandé à GitHub. Aucun téléchargement, aucune donnée envoyée.")
                    if m.updateChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Key(label: "Chercher", symbol: "arrow.down.circle") {
                            m.checkForUpdate(manual: true)
                        }
                    }
                    Key(label: "Dépôt", symbol: "arrow.up.right.square") { m.openRepo() }
                }

                if m.updateNewer, let latest = m.updateLatest {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11)).foregroundStyle(Tone.accent)
                        Text("La version \(latest) est disponible. À lancer dans le Terminal :")
                            .font(.system(size: 12)).foregroundStyle(Tone.accent)
                        Text(UpdateCheck.command)
                            .font(.value(12)).foregroundStyle(Tone.txt1)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Tone.bg0, in: RoundedRectangle(cornerRadius: 6))
                        Key(label: "Copier", symbol: "doc.on.doc") { m.copyUpdateCommand() }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Tone.accentDim, in: RoundedRectangle(cornerRadius: Metric.radius))
                } else if let msg = m.updateMessage {
                    note(msg)
                }
            }
        }
    }

    // MARK: Pièces communes

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func row(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Tone.txt1).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Une explication tient en une ligne ou deux. Le reste va dans l'infobulle
    /// de la commande qu'il explique.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(Tone.txt2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
