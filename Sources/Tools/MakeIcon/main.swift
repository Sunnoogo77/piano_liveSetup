import AppKit
import Foundation

// Fabrique l'icône de l'application : le même motif que l'écran de démarrage,
// posé sur la pastille arrondie des icônes macOS. Générée à la construction,
// donc aucune image binaire n'est versionnée.

// Deux usages :
//   makeicon <dossier>          jeu d'icônes macOS (.iconset)
//   makeicon --web <dossier>    icônes pour l'écran d'accueil d'un iPad
//
// Les icônes web sont dessinées à fond perdu : iOS et Android appliquent
// eux-mêmes le masque arrondi, et une pastille déjà arrondie donnerait une
// icône rentrée dans son coin.

var args = Array(CommandLine.arguments.dropFirst())
var web = false
if args.first == "--web" { web = true; args.removeFirst() }
let out = args.first ?? (web ? "build/web-icons" : "build/AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let teal = NSColor(srgbRed: 0.310, green: 0.820, blue: 0.773, alpha: 1)
let bgTop = NSColor(srgbRed: 0.106, green: 0.125, blue: 0.157, alpha: 1)
let bgBottom = NSColor(srgbRed: 0.035, green: 0.043, blue: 0.059, alpha: 1)

func draw(size: CGFloat, bleed: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Pastille : proportions des icônes macOS (824 sur 1024, rayon 185).
    // À fond perdu, on remplit tout le carré : le système fera le masque.
    let inset = bleed ? 0 : size * 0.0977
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = bleed ? 0 : size * 0.1807
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    squircle.addClip()
    let gradient = NSGradient(colors: [bgTop, bgBottom])!
    gradient.draw(in: rect, angle: -90)

    // Reflet très discret en haut, comme sur les icônes système.
    let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.07),
                                    NSColor.white.withAlphaComponent(0.0)])!
    gloss.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    ctx.restoreGState()

    // Liseré — inutile à fond perdu, le masque du système le mangerait.
    if !bleed {
        NSColor.white.withAlphaComponent(0.10).setStroke()
        squircle.lineWidth = max(1, size * 0.004)
        squircle.stroke()
    }

    // Le motif de touches, en sarcelle, centré.
    // On ne peut pas « teinter » un NSImage en le dessinant : on fabrique une
    // image pleine de la couleur voulue, découpée par l'alpha du symbole.
    let symbolSize = size * (bleed ? 0.42 : 0.50)
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "pianokeys", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let tinted = NSImage(size: s)
        tinted.lockFocus()
        teal.set()
        NSRect(origin: .zero, size: s).fill()
        symbol.draw(in: NSRect(origin: .zero, size: s), from: .zero,
                    operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()

        let target = NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                            width: s.width, height: s.height)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: size * 0.045,
                      color: teal.withAlphaComponent(0.5).cgColor)
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()
    }

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, _ pixels: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: out + "/" + name))
}

if web {
    for pixels in [180, 192, 512] {
        write(draw(size: CGFloat(pixels), bleed: true), pixels, "icon-\(pixels).png")
    }
    print("icônes web écrites : \(out)")
} else {
    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                            (256, 1), (256, 2), (512, 1), (512, 2)] {
        let pixels = points * scale
        let img = draw(size: CGFloat(pixels))
        write(img, pixels, "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")
    }
    print("iconset écrit : \(out)")
}
