// Renders the styled installer background for the release dmg.
// Usage: swift scripts/render-dmg-background.swift <output.png>
// The PNG is written at 2x pixels with a 660x400pt logical size so Finder
// draws it retina-sharp at the window size set by scripts/build-dmg.sh.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background.swift <output.png>\n".utf8))
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let pointSize = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
let pixelWide = Int(pointSize.width * scale)
let pixelHigh = Int(pointSize.height * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWide,
    pixelsHigh: pixelHigh,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext
cg.scaleBy(x: scale, y: scale)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Canvas: the app's dark gradient.
let bounds = NSRect(origin: .zero, size: pointSize)
NSGradient(colors: [color(0x16161B), color(0x0E0E12)])!
    .draw(in: bounds, angle: -70)

// Soft brand-blue glows behind each icon well so the drop targets read
// as two lit "slots" (AppKit coordinates: origin bottom-left, so the
// icon row sits at y ≈ 230 for a row placed 170pt from the top).
let iconRowY: CGFloat = 230
for glowX: CGFloat in [165, 495] {
    let glow = NSGradient(
        starting: color(0x3B82F6, glowX == 165 ? 0.16 : 0.10),
        ending: color(0x3B82F6, 0)
    )!
    glow.draw(
        fromCenter: NSPoint(x: glowX, y: iconRowY), radius: 0,
        toCenter: NSPoint(x: glowX, y: iconRowY), radius: 130,
        options: []
    )
}

// Dashed arrow between the two icon wells.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: iconRowY))
arrow.line(to: NSPoint(x: 384, y: iconRowY))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.setLineDash([0.1, 14], count: 2, phase: 0)
color(0xFFFFFF, 0.38).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 384, y: iconRowY + 13))
head.line(to: NSPoint(x: 402, y: iconRowY))
head.line(to: NSPoint(x: 384, y: iconRowY - 13))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
color(0xFFFFFF, 0.38).setStroke()
head.stroke()

// Caption under the icon row.
func drawText(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(0xFFFFFF, alpha),
    ]
    let text = NSAttributedString(string: string, attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(x: (pointSize.width - textSize.width) / 2, y: centerY - textSize.height / 2))
}

drawText("Drag WinterVoice into Applications to install", size: 14, weight: .medium, alpha: 0.45, centerY: 96)
drawText("Speak anywhere. It types for you.", size: 12, weight: .regular, alpha: 0.24, centerY: 70)

NSGraphicsContext.restoreGraphicsState()

// The logical (point) size must be stamped so Finder renders the 2x
// pixels at 660x400 instead of doubling the window.
rep.size = pointSize
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outputURL)
print("wrote \(outputURL.path)")
