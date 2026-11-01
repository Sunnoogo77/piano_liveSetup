import SwiftUI
import AppKit

// MARK: - Écran « Enregistrer »

struct RecordScreen: View {
    @ObservedObject var m: RigModel

    var body: some View {
        VStack(spacing: Metric.gap) {
            Panel {
                HStack(alignment: .center, spacing: 20) {
                    Button { m.toggleRecording() } label: {
                        ZStack {
                            Circle()
                                .fill(m.isRecording ? Tone.hot : Tone.bg2)
                                .frame(width: 68, height: 68)
                            Circle().strokeBorder(m.isRecording ? Tone.hot.opacity(0.4) : Tone.line2,
                                                  lineWidth: 2).frame(width: 78, height: 78)
                            Image(systemName: m.isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: m.isRecording ? 24 : 30, weight: .medium))
                                .foregroundStyle(m.isRecording ? .white : Tone.hot)
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Caption(text: m.isRecording ? "Enregistrement en cours" : "Prêt à enregistrer",
                                color: m.isRecording ? Tone.hot : Tone.txt2)
                        Text(timeLabel)
                            .font(.system(size: 36, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(m.isRecording ? Tone.txt0 : Tone.txt2)
                        Text(m.isRecording ? "\(m.recNotes) note\(m.recNotes == 1 ? "" : "s") · \(m.preset.name)"
                                           : "Le son actif et la transposition sont enregistrés avec la prise")
                            .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                    }
                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $m.recordAudio) {
                            Text("Enregistrer aussi l'audio (WAV 24 bits)")
                                .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                        }
                        .toggleStyle(.switch).tint(Tone.accent).disabled(m.isRecording)
                        HStack(spacing: 8) {
                            Caption(text: "Tempo de la partition")
                            Text("\(Int(m.tempo)) bpm").font(.value(11)).foregroundStyle(Tone.txt1)
                        }
                        Slider(value: $m.tempo, in: 40...200, step: 1)
                            .controlSize(.small).tint(Tone.accent)
                            .frame(width: 230).disabled(m.isRecording)
                    }
                    .frame(width: 250)
                }
            }

            Panel(title: "Ce qui est produit à chaque prise") {
                HStack(alignment: .top, spacing: 12) {
                    produced("waveform", "audio.wav", "Le son exact qui sort, 24 bits stéréo")
                    produced("pianokeys", "performance.mid", "Rejouable sur le piano, timing exact")
                    produced("doc.richtext", "partition.musicxml", "Partition quantifiée, deux portées")
                    produced("music.quarternote.3", "accords.txt", "Grille d'accords horodatée")
                }
            }

            Panel(title: "Prises enregistrées", trailing: AnyView(
                Button { m.refreshTakes() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        .foregroundStyle(Tone.txt2)
                }.buttonStyle(.plain))) {
                if m.takes.isEmpty {
                    Text("Aucune prise pour l'instant.")
                        .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                } else {
                    Scroll {
                        VStack(spacing: 6) {
                            ForEach(m.takes) { t in takeRow(t) }
                        }
                    }
                    .frame(maxHeight: 230)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var timeLabel: String {
        let s = Int(m.recSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func produced(_ symbol: String, _ name: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tone.accent)
                Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(Tone.txt0)
            }
            Text(desc).font(.system(size: 11)).foregroundStyle(Tone.txt2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Tone.bg2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

struct DevicesScreen: View {
    @ObservedObject var m: RigModel

    var body: some View {
        Scroll {
            VStack(spacing: Metric.gap) {
                HStack(alignment: .top, spacing: Metric.gap) {
                    Panel(title: "Clavier MIDI") {
                        VStack(alignment: .leading, spacing: 8) {
                            if m.engine.midiSourceNames.isEmpty {
                                row("exclamationmark.triangle", "Aucun clavier détecté", Tone.warn)
                                Text("Branchez le piano en USB et allumez-le. La détection est permanente : dès qu'il apparaît, l'application s'y connecte, coupe son son interne et bascule la sortie audio dessus s'il sait la recevoir. Rien à faire de votre côté.")
                                    .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(m.engine.midiSourceNames, id: \.self) { n in
                                    row("pianokeys", n, Tone.ok)
                                }
                                row("arrow.up.right", "Retour vers : \(m.engine.midiDestinationName)", Tone.txt1)
                            }
                            Divider().overlay(Tone.line)
                            HStack {
                                Toggle(isOn: Binding(get: { m.localSilenced },
                                                     set: { _ in m.toggleLocal() })) {
                                    Text("Couper le son interne du clavier")
                                        .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                                }
                                .toggleStyle(.switch).tint(Tone.accent)
                            }
                            Text("Message MIDI standard (CC 122), compris par tous les fabricants. Rétabli à la fermeture, et de toute façon oublié par l'instrument à l'extinction.")
                                .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                                .fixedSize(horizontal: false, vertical: true)
                            Key(label: "Rechercher les appareils", symbol: "arrow.clockwise", wide: true) {
                                m.engine.rescanMIDI(); m.refreshDevices()
                            }
                            if let err = m.engine.midiClientError {
                                Text(err).font(.system(size: 12)).foregroundStyle(Tone.hot)
                            } else {
                                Text(m.engine.midiNotifications == 0
                                     ? "Détection à chaud active — aucun changement vu depuis le lancement."
                                     : (m.engine.midiNotifications == 1
                                        ? "Détection à chaud active — un changement vu depuis le lancement."
                                        : "Détection à chaud active — \(m.engine.midiNotifications) changements vus depuis le lancement."))
                                    .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                            }
                        }
                    }

                    Panel(title: "Sortie audio") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(m.engine.statusAudio)
                                .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                            Divider().overlay(Tone.line)
                            ForEach(m.audioDevices, id: \.self) { d in
                                Button { m.chooseAudioDevice(d) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: m.engine.audioDeviceLabel == d
                                              ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(m.engine.audioDeviceLabel == d ? Tone.accent : Tone.txt2)
                                        Text(d).font(.system(size: 12))
                                            .foregroundStyle(m.engine.audioDeviceLabel == d ? Tone.txt0 : Tone.txt1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                            Divider().overlay(Tone.line)
                            Toggle(isOn: Binding(get: { m.followOutput },
                                                 set: { m.setFollowOutput($0) })) {
                                Text("Suivre le clavier automatiquement")
                                    .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                            }
                            .toggleStyle(.switch).tint(Tone.accent)
                            Text("Beaucoup de pianos numériques renvoient le son du Mac dans leurs haut-parleurs par le câble USB. Quand c'est le cas et que cette option est active, la sortie bascule dessus dès que l'instrument est allumé. Décochez-la pour imposer votre propre choix — par exemple un micro virtuel pour Teams ou Zoom.")
                                .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Panel(title: "Contrôle à distance") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(get: { m.remoteOn }, set: { _ in m.toggleRemote() })) {
                                Text("Publier une page de commande sur le réseau local")
                                    .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                            }
                            .toggleStyle(.switch).tint(Tone.accent)
                            Spacer(minLength: 0)
                            if m.remoteOn {
                                HStack(spacing: 6) {
                                    Circle().fill(Tone.ok).frame(width: 6, height: 6)
                                    Text("en service").font(.system(size: 12)).foregroundStyle(Tone.ok)
                                }
                            }
                        }

                        if m.remoteOn {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 12) {
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
                                                    Image(systemName: "doc.on.doc")
                                                        .font(.system(size: 11))
                                                    Text(a).font(.system(size: 11, design: .monospaced))
                                                        .lineLimit(1).truncationMode(.middle)
                                                }
                                                .foregroundStyle(Tone.txt1)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copier l'adresse")
                                        }
                                    }
                                    Text("Sur l'iPad ou le téléphone, scannez le code ou ouvrez l'adresse dans le navigateur. Le Mac continue de faire le son : l'appareil ne sert que de commande.")
                                        .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Le premier lancement peut faire apparaître une demande du pare-feu macOS : autorisez les connexions entrantes.")
                                        .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if let first = m.remoteAddresses.first {
                                    VStack(spacing: 6) {
                                        QRCode(text: first)
                                        Caption(text: "à scanner")
                                    }
                                }
                            }
                        } else {
                            Text("Une fois activée, une page s'ouvre depuis n'importe quel navigateur du réseau : sons, transposition, niveaux, égaliseur, arrêt des notes et enregistrement. Rien à installer sur la tablette.")
                                .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let msg = m.remoteMessage {
                            Text(msg).font(.system(size: 12)).foregroundStyle(Tone.warn)
                        }
                    }
                }

                Panel(title: "Version et mises à jour") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Version \(AppInfo.version)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Tone.txt0)
                            Text("\(AppInfo.commit) · \(AppInfo.built)")
                                .font(.system(size: 12)).foregroundStyle(Tone.txt2)
                            Spacer(minLength: 0)
                            if m.updateChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Key(label: "Chercher une mise à jour", symbol: "arrow.down.circle") {
                                    m.checkForUpdate(manual: true)
                                }
                            }
                        }

                        if m.updateNewer, let latest = m.updateLatest {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11)).foregroundStyle(Tone.accent)
                                    Text("La version \(latest) est disponible.")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Tone.accent)
                                }
                                Text("Rien n'est installé sans vous. Lancez cette commande dans le Terminal :")
                                    .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                                HStack(spacing: 8) {
                                    Text(UpdateCheck.command)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Tone.txt1)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 8).padding(.vertical, 6)
                                        .background(Tone.bg0, in: RoundedRectangle(cornerRadius: 6))
                                    Key(label: "Copier", symbol: "doc.on.doc") { m.copyUpdateCommand() }
                                }
                            }
                            .padding(12)
                            .background(Tone.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        } else if let msg = m.updateMessage {
                            Text(msg).font(.system(size: 12)).foregroundStyle(Tone.txt1)
                        }

                        Divider().overlay(Tone.line)
                        Toggle(isOn: Binding(get: { m.engine.config.checkUpdates },
                                             set: { m.setCheckUpdates($0) })) {
                            Text("Regarder au lancement s'il existe une version plus récente")
                                .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                        }
                        .toggleStyle(.switch).tint(Tone.accent)
                        HStack(spacing: 12) {
                            Text("Seul le numéro de version est demandé à GitHub. Aucun téléchargement, aucune donnée envoyée.")
                                .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Key(label: "Voir le dépôt", symbol: "arrow.up.right.square") { m.openRepo() }
                        }
                    }
                }

                Panel(title: "Entrée micro") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Picker("", selection: $m.micDeviceID) {
                                ForEach(m.micDevices, id: \.id) { d in
                                    Text(d.name).tag(d.id)
                                }
                            }
                            .labelsHidden().frame(width: 260).disabled(m.micOn)
                            Key(label: m.micOn ? "Arrêter l'entrée" : "Activer l'entrée",
                                symbol: m.micOn ? "mic.slash.fill" : "mic.fill",
                                tint: m.micOn ? Tone.hot : Tone.txt0, filled: false) { m.toggleMic() }
                            Toggle(isOn: Binding(get: { m.micMonitoring },
                                                 set: { m.setMicMonitoring($0) })) {
                                Text("Envoyer dans la sortie")
                                    .font(.system(size: 11)).foregroundStyle(Tone.txt1)
                            }
                            .toggleStyle(.switch).tint(Tone.warn).disabled(!m.micOn)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 4) {
                                Caption(text: "Entrée")
                                LevelMeter(left: m.micPeakDB, right: m.micPeakDB,
                                           holdL: m.micPeakDB, holdR: m.micPeakDB, height: 6)
                                    .frame(width: 110)
                            }
                        }

                        // L'autorisation d'abord : sans elle, le périphérique
                        // s'ouvre sans erreur et n'envoie que du silence.
                        HStack(spacing: 8) {
                            Image(systemName: m.micAuth == .authorized
                                  ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(m.micAuth == .authorized ? Tone.ok : Tone.warn)
                            Text("Autorisation macOS : \(m.micAuth.human)")
                                .font(.system(size: 12))
                                .foregroundStyle(m.micAuth == .authorized ? Tone.txt2 : Tone.warn)
                            if m.micAuth == .denied || m.micAuth == .restricted {
                                Key(label: "Ouvrir les réglages", symbol: "gear") { m.openMicSettings() }
                                Key(label: "Revérifier", symbol: "arrow.clockwise") { m.refreshMicAuth() }
                            }
                            Key(label: "Chercher les entrées", symbol: "arrow.clockwise") {
                                m.refreshDevices()
                            }
                            Spacer(minLength: 0)
                        }

                        if m.micOn && !m.micMonitoring {
                            Text("L'entrée est ouverte mais l'écoute est coupée : rien ne sort. Activez « Envoyer dans la sortie » pour l'entendre.")
                                .font(.system(size: 12)).foregroundStyle(Tone.txt1)
                        }

                        if m.micMonitoring {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11)).foregroundStyle(Tone.warn)
                                Text("Micro renvoyé dans les haut-parleurs : risque de larsen. Baissez le volume avant d'ouvrir.")
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

                        HStack(spacing: 20) {
                            Fader(title: "Gain du micro",
                                  value: Binding(get: { m.micGain }, set: { m.setMicGain($0) }),
                                  range: 0...3, format: { String(format: "%+.1f dB", 20 * log10(max(0.001, $0))) })
                                .frame(width: 240)
                            Fader(title: "Compresseur voix",
                                  value: Binding(get: { m.micComp }, set: { m.setMicComp($0) }),
                                  )
                                .frame(width: 240)
                            Spacer(minLength: 0)
                        }

                        Divider().overlay(Tone.line)
                        HStack {
                            Caption(text: "Égaliseur de la voix")
                            Spacer()
                            Key(label: "Réglage de départ", symbol: "arrow.counterclockwise", height: 26) {
                                m.resetMicEQ()
                            }
                        }
                        Scroll(axis: .horizontal, flattenable: false) {
                            HStack(spacing: 8) {
                                ForEach(m.micBands.indices, id: \.self) { i in
                                    EQBandCell(index: i, band: $m.micBands[i],
                                               isSelected: m.micSelectedBand == i,
                                               onSelect: { m.micSelectedBand = i },
                                               onChange: { m.commitMicBands() })
                                }
                            }
                        }
                        .frame(height: 78)
                        Text("L'égaliseur du micro est indépendant de celui du piano. Le réglage de départ coupe sous 95 Hz, dégage le bas-médium et relève la présence — un point de départ classique pour une voix.")
                            .font(.system(size: 11)).foregroundStyle(Tone.txt2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

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
}
