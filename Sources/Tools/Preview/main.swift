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
            notes: [Int] = [], history: [Int] = []) {
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
    if fakeSpectrum { m.engine.spectrum.injectTestSignal() }
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

MainActor.assumeIsolated {
    let chord: [Int] = [48, 55, 64, 67, 70, 74]          // Do9, voicing de pianiste
    render("tab-play",    width: 1440, height: 900, presetIndex: 23, tab: .play, notes: chord)
    render("tab-eq",      width: 1440, height: 900, presetIndex: 0,  tab: .eq)
    render("tab-chords",  width: 1440, height: 900, presetIndex: 0,  tab: .chords,
           notes: chord, history: [60, 65, 55, 62, 57, 50])
    render("tab-keys",    width: 1440, height: 900, presetIndex: 29, tab: .keys, notes: chord)
    render("tab-record",  width: 1440, height: 900, presetIndex: 0,  tab: .record)
    render("tab-devices", width: 1440, height: 1000, presetIndex: 0, tab: .devices)
    render("ui-min",      width: 1020, height: 700, sidebar: 230, presetIndex: 7, tab: .play,
           notes: chord)
}
