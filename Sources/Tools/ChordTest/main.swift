import Foundation

// Vérification de la reconnaissance d'accords sur des voicings connus.

struct Case { let notes: [Int]; let expect: String; let label: String }

let cases: [Case] = [
    // triades, position fondamentale
    .init(notes: [60, 64, 67],              expect: "C",        label: "Do majeur"),
    .init(notes: [60, 63, 67],              expect: "Cm",       label: "Do mineur"),
    .init(notes: [60, 63, 66],              expect: "Cdim",     label: "Do diminué"),
    .init(notes: [60, 64, 68],              expect: "Caug",     label: "Do augmenté"),
    .init(notes: [60, 65, 67],              expect: "Csus4",    label: "Do sus4"),
    .init(notes: [60, 62, 67],              expect: "Csus2",    label: "Do sus2"),
    // renversements
    .init(notes: [64, 67, 72],              expect: "C/E",      label: "Do majeur, 1er renversement"),
    .init(notes: [67, 72, 76],              expect: "C/G",      label: "Do majeur, 2e renversement"),
    // La-Do-Mi-Sol : Am7 est la lecture standard, pas Do6/La
    .init(notes: [57, 60, 64, 67],          expect: "Am7",      label: "La mineur 7 (= Do6/La)"),
    // septièmes
    .init(notes: [60, 64, 67, 70],          expect: "C7",       label: "Do septième"),
    .init(notes: [60, 64, 67, 71],          expect: "Cmaj7",    label: "Do majeur 7"),
    .init(notes: [60, 63, 67, 70],          expect: "Cm7",      label: "Do mineur 7"),
    .init(notes: [60, 63, 66, 70],          expect: "Cm7♭5",    label: "Do demi-diminué"),
    .init(notes: [60, 63, 66, 69],          expect: "Cdim7",    label: "Do diminué 7"),
    .init(notes: [60, 65, 67, 70],          expect: "C7sus4",   label: "Do 7sus4"),
    .init(notes: [60, 63, 67, 71],          expect: "Cm(maj7)", label: "Do mineur majeur 7"),
    // sixtes et ajoutées
    .init(notes: [60, 64, 67, 69],          expect: "C6",       label: "Do sixte"),
    .init(notes: [60, 63, 67, 69],          expect: "Cm6",      label: "Do mineur sixte"),
    .init(notes: [60, 62, 64, 67],          expect: "Cadd9",    label: "Do ajoutée 9"),
    // neuvièmes
    .init(notes: [60, 64, 67, 70, 74],      expect: "C9",       label: "Do neuvième"),
    .init(notes: [60, 64, 67, 71, 74],      expect: "Cmaj9",    label: "Do majeur 9"),
    .init(notes: [60, 63, 67, 70, 74],      expect: "Cm9",      label: "Do mineur 9"),
    // voicings de jazz, quinte omise
    .init(notes: [60, 64, 70, 74],          expect: "C9",       label: "Do 9 sans quinte"),
    .init(notes: [60, 64, 71],              expect: "Cmaj7",    label: "Do maj7 sans quinte"),
    .init(notes: [60, 63, 70],              expect: "Cm7",      label: "Do m7 sans quinte"),
    // autres toniques, y compris bémols
    .init(notes: [63, 67, 70],              expect: "E♭",       label: "Mi bémol majeur"),
    .init(notes: [58, 62, 65, 68],          expect: "B♭7",      label: "Si bémol 7"),
    .init(notes: [66, 70, 73],              expect: "F♯",       label: "Fa dièse majeur (enharmonique Sol♭)"),
    .init(notes: [62, 66, 69, 73],          expect: "Dmaj7",    label: "Ré majeur 7"),
    .init(notes: [65, 69, 72, 76],          expect: "Fmaj7",    label: "Fa majeur 7"),
    .init(notes: [69, 72, 76, 77],          expect: "Fmaj7/A",  label: "Fa maj7, 1er renversement"),
    // voicings larges, avec doublures
    .init(notes: [36, 48, 52, 55, 60, 64],  expect: "C",        label: "Do majeur sur 3 octaves"),
    .init(notes: [41, 48, 60, 64, 69],      expect: "Fmaj7",    label: "Fa maj7, voicing large"),
    .init(notes: [41, 48, 60, 62, 69],      expect: "F6",       label: "Fa sixte, voicing large"),
    // cas réellement ambigus et voicings de pianiste
    .init(notes: [62, 65, 69, 72],          expect: "Dm7",      label: "Ré mineur 7 (= Fa6/Ré)"),
    .init(notes: [55, 59, 62, 65, 69],      expect: "G9",       label: "Sol 9, main large"),
    .init(notes: [48, 64, 70, 74],          expect: "C9",       label: "Do 9, voicing sans quinte ni basse"),
    .init(notes: [52, 56, 62, 67],          expect: "E7♯9",     label: "Mi 7 dièse 9 (accord d'Hendrix)"),
    .init(notes: [60, 62, 65, 67, 70],      expect: "Cm11",     label: "Do mineur 11"),
    .init(notes: [47, 50, 54],              expect: "Bm",       label: "Si mineur"),
    .init(notes: [47, 50, 54, 57],          expect: "Bm7",      label: "Si mineur 7"),
    // intervalles et note seule
    .init(notes: [60],                      expect: "C",        label: "note seule"),
    .init(notes: [60, 67],                  expect: "C5",       label: "quinte à vide"),
]

var fails = 0
for c in cases {
    let r = ChordDetector.detect(c.notes)
    let ok = r.symbol == c.expect
    if !ok { fails += 1 }
    let conf = String(format: "%3.0f %%", r.confidence * 100)
    print("  \(ok ? "OK   " : "ÉCHEC") \(c.label.padding(toLength: 30, withPad: " ", startingAt: 0)) → \(r.symbol.padding(toLength: 10, withPad: " ", startingAt: 0)) \(ok ? "" : "(attendu \(c.expect))")  [\(conf), \(r.quality)]")
}
print("\n\(cases.count - fails)/\(cases.count) accords reconnus")
exit(fails == 0 ? 0 : 1)
