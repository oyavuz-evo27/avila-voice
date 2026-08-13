// Generates the app icon (silver/graphite, macOS 26 style) and the menu bar template
// icon from Resources/Logo.png. Run: swift Scripts/make_icon.swift
import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logoURL = root.appendingPathComponent("Resources/Logo.png")
let outIcon = root.appendingPathComponent("build/icon/AppIcon_1024.png")
let outMenuBar = root.appendingPathComponent("Sources/AvilaVoice/Resources/MenuBarIcon.png")

guard let logo = NSImage(contentsOf: logoURL) else { fatalError("Logo.png not found") }

// MARK: silver version of the logo (desaturate + lift brightness)
func silverLogo() -> NSImage {
    guard let tiff = logo.tiffRepresentation, let ci = CIImage(data: tiff) else { fatalError() }
    let mono = CIFilter(name: "CIColorControls", parameters: [
        kCIInputImageKey: ci,
        kCIInputSaturationKey: 0.0,
        kCIInputBrightnessKey: 0.32,
        kCIInputContrastKey: 0.95,
    ])!.outputImage!
    let rep = NSCIImageRep(ciImage: mono)
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: app icon 1024×1024 — graphite rounded rect, silver logo
let iconRep = bitmap(1024)
draw(into: iconRep) {
    let rect = NSRect(x: 96, y: 96, width: 832, height: 832)
    let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)

    NSGradient(starting: NSColor(calibratedWhite: 0.33, alpha: 1),
               ending: NSColor(calibratedWhite: 0.10, alpha: 1))!
        .draw(in: path, angle: -90)

    // subtle inner highlight at the top edge
    path.addClip()
    NSGradient(starting: NSColor(calibratedWhite: 1, alpha: 0.16),
               ending: NSColor(calibratedWhite: 1, alpha: 0))!
        .draw(in: NSRect(x: 96, y: 688, width: 832, height: 240), angle: -90)

    let silver = silverLogo()
    let logoSize: CGFloat = 600
    silver.draw(in: NSRect(x: (1024 - logoSize) / 2, y: (1024 - logoSize) / 2,
                           width: logoSize, height: logoSize),
                from: .zero, operation: .sourceOver, fraction: 1.0)
}
savePNG(iconRep, to: outIcon)

// MARK: menu bar template icon 36×36 (18 pt @2x) — black bars + alpha
let mbRep = bitmap(36)
draw(into: mbRep) {
    logo.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36),
              from: .zero, operation: .sourceOver, fraction: 1.0)
}
// template images are pure black + alpha
if let data = mbRep.bitmapData {
    let bpr = mbRep.bytesPerRow
    for y in 0..<36 {
        for x in 0..<36 {
            let p = data + y * bpr + x * 4
            p[0] = 0; p[1] = 0; p[2] = 0 // keep alpha p[3]
        }
    }
}
savePNG(mbRep, to: outMenuBar)

print("ok: \(outIcon.path)")
print("ok: \(outMenuBar.path)")
