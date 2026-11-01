import SwiftUI
import AppKit

// Rend l'interface hors écran et l'enregistre en PNG, pour pouvoir la regarder
// et l'ajuster sans dépendre d'une capture d'écran.

Flat.scrolls = true
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

@MainActor
func render(_ name: String, width: CGFloat, height: CGFloat, sidebar: CGFloat = 262,
            presetIndex: Int = 0, fakeSpectrum: Bool = true, tab: Tab = .eq,
            notes: [Int] = [], history: [Int] = [], keyboard: Bool = true,
            mic: Bool = false) {
    let m = RigModel()
    m.ready = true
    m.presetIndex = min(presetIndex, m.presets.count - 1)
    m.bands = m.preset.eqBands
    m.layerMix = m.preset.layerMix
    m.drive = m.preset.drive
    m.tremRate = m.preset.tremRate
    m.tremDepth = m.preset.tremDepth
    m.comp = m.preset.compAmount
    m.transpose = presetIndex % 3 == 0 ? 0 : -3
    m.peakDBL = -11; m.peakDBR = -14; m.holdL = -7; m.holdR = -9
    m.held = 4; m.midiLive = true
    m.engine.chain.updateEQ(m.bands)
    m.commitMicBands()
    if fakeSpectrum { m.engine.spectrum.injectTestSignal() }
    if mic {
        m.micOn = true
        m.micPeakDB = -16
        m.engine.mic.spectrum.injectTestSignal()
    }
    m.tab = tab
    if !notes.isEmpty {
        m.sounding = notes
        m.chord = ChordDetector.detect(notes)
    }
    if !history.isEmpty {
        m.chordHistory = history.map { ChordDetector.detect([$0, $0 + 4, $0 + 7, $0 + 11]) }
    }
    m.isRecording = (tab == .record)
    m.recSeconds = 94; m.recNotes = 412
    m.hasKeyboard = keyboard
    m.refreshDevices()

    let view = HStack(spacing: 0) {
        SidebarView(m: m).frame(width: sidebar).clipped()
        Divider().overlay(Tone.line)
        StageView(m: m)
    }
    .frame(width: width, height: height)
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let img = renderer.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("échec de rendu : \(name)"); return
    }
    let path = outDir + "/" + name + ".png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("écrit \(path)  \(Int(width))×\(Int(height))")
}

/// La bibliothèque seule, quelques familles repliées : c'est l'image qui montre
/// le mieux à quoi sert le pliage.
@MainActor
func renderSidebar(_ name: String, width: CGFloat = 300, height: CGFloat = 596) {
    let m = RigModel()
    m.ready = true
    m.presetIndex = idx("Violon")
    // Tout replié sauf une famille : l'image montre les deux états à la fois.
    let shut = Set(Category.allCases).subtracting([.strings])
    // Le champ de recherche est une TextField : le rendu hors écran ne sait pas
    // la dessiner (voir AGENTS.md). On cadre juste en dessous.
    let top: CGFloat = 52
    let view = SidebarView(m: m, closed: shut)
        .frame(width: width, height: height + top, alignment: .top)
        .padding(.top, -top)
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("échec de rendu : \(name)"); return
    }
    try? png.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png"))
    print("écrit \(outDir)/\(name).png  \(Int(width))×\(Int(height))")
}

/// Un son se désigne par son nom : les numéros bougent dès qu'une famille
/// s'ajoute au milieu de la bibliothèque.
func idx(_ name: String) -> Int {
    Library.all().firstIndex { $0.name == name } ?? 0
}

MainActor.assumeIsolated {
    let chord: [Int] = [48, 55, 64, 67, 70, 74]          // Do9, voicing de pianiste
    render("tab-play",    width: 1440, height: 900, presetIndex: idx("Grand + Choir"),
           tab: .play, notes: chord)
    render("tab-eq",      width: 1440, height: 900, presetIndex: 0,  tab: .eq)
    render("tab-chords",  width: 1440, height: 900, presetIndex: 0,  tab: .chords,
           notes: chord, history: [60, 65, 55, 62, 57, 50])
    render("tab-keys",    width: 1440, height: 900, presetIndex: idx("Nappe / Piano"),
           tab: .keys, notes: chord)
    render("tab-record",  width: 1440, height: 900, presetIndex: 0,  tab: .record)
    render("tab-devices", width: 1440, height: 1000, presetIndex: 0, tab: .devices, mic: true)
    render("tab-devices-large", width: 1728, height: 1060, presetIndex: 0, tab: .devices,
           mic: true)
    render("ui-min",      width: 1020, height: 700, sidebar: 230,
           presetIndex: idx("Suitcase Tremolo"), tab: .play, notes: chord)
    render("tab-play-waiting", width: 1440, height: 900, presetIndex: 0, tab: .play,
           keyboard: false)
    renderSidebar("library")
}
