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

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pointSize.width * scale),
    pixelsHigh: Int(pointSize.height * scale),
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
context.cgContext.scaleBy(x: scale, y: scale)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// AppKit coordinates: origin bottom-left. Design positions are given from
// the window top, so convert through `fromTop`.
func fromTop(_ y: CGFloat) -> CGFloat { pointSize.height - y }

// Canvas gradient with a faint blue bloom rising from the bottom edge.
let bounds = NSRect(origin: .zero, size: pointSize)
NSGradient(colors: [color(0x1A1A21), color(0x0C0C10)])!.draw(in: bounds, angle: -90)
NSGradient(
    starting: color(0x3B82F6, 0.10), ending: color(0x3B82F6, 0)
)!.draw(
    fromCenter: NSPoint(x: pointSize.width / 2, y: -80), radius: 0,
    toCenter: NSPoint(x: pointSize.width / 2, y: -80), radius: 340,
    options: []
)

// Brand waveform mark, top center.
let waveWeights: [CGFloat] = [0.45, 0.7, 1.0, 1.2, 1.0, 0.7, 0.45]
let waveMaxHeight: CGFloat = 20
let waveBarWidth: CGFloat = 4
let waveSpacing: CGFloat = 4
let waveTotalWidth = CGFloat(waveWeights.count) * waveBarWidth
    + CGFloat(waveWeights.count - 1) * waveSpacing
let waveCenterY = fromTop(52)
var waveX = (pointSize.width - waveTotalWidth) / 2
for weight in waveWeights {
    let barHeight = waveMaxHeight * weight
    let bar = NSBezierPath(
        roundedRect: NSRect(
            x: waveX, y: waveCenterY - barHeight / 2,
            width: waveBarWidth, height: barHeight
        ),
        xRadius: waveBarWidth / 2, yRadius: waveBarWidth / 2
    )
    NSGradient(colors: [color(0x60A5FA), color(0x2563EB)])!
        .draw(in: bar, angle: -90)
    waveX += waveBarWidth + waveSpacing
}

func drawCenteredText(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, topY: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(0xFFFFFF, alpha),
        .kern: weight == .semibold ? 0.2 : 0,
    ]
    let text = NSAttributedString(string: string, attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(
        x: (pointSize.width - textSize.width) / 2,
        y: fromTop(topY) - textSize.height / 2
    ))
}

drawCenteredText("Install WinterVoice", size: 19, weight: .semibold, alpha: 0.92, topY: 86)

// Icon wells: rounded plates that seat the app icon and the Applications
// folder so the drop targets read as intentional slots.
let wellCenters: [CGFloat] = [165, 495]
let wellCenterYFromTop: CGFloat = 200
for (index, centerX) in wellCenters.enumerated() {
    let well = NSRect(
        x: centerX - 76, y: fromTop(wellCenterYFromTop) - 76,
        width: 152, height: 152
    )
    let path = NSBezierPath(roundedRect: well, xRadius: 32, yRadius: 32)
    // Soft blue lift behind the well, stronger on the app side.
    NSGradient(
        starting: color(0x3B82F6, index == 0 ? 0.14 : 0.08),
        ending: color(0x3B82F6, 0)
    )!.draw(
        fromCenter: NSPoint(x: centerX, y: fromTop(wellCenterYFromTop)), radius: 0,
        toCenter: NSPoint(x: centerX, y: fromTop(wellCenterYFromTop)), radius: 150,
        options: []
    )
    color(0xFFFFFF, 0.045).setFill()
    path.fill()

    // Nameplate band across the well bottom, where Finder draws the icon
    // label. Finder colors labels from the SYSTEM appearance (black in
    // Light Mode, white in Dark Mode), not from the background picture —
    // a ~50% gray is the only tone that stays readable under both.
    let bandHeight: CGFloat = 34
    let band = NSBezierPath()
    let wellBottom = well.minY
    band.move(to: NSPoint(x: well.minX, y: wellBottom + bandHeight))
    band.line(to: NSPoint(x: well.maxX, y: wellBottom + bandHeight))
    band.line(to: NSPoint(x: well.maxX, y: wellBottom + 32))
    band.appendArc(
        from: NSPoint(x: well.maxX, y: wellBottom),
        to: NSPoint(x: well.maxX - 32, y: wellBottom),
        radius: 32
    )
    band.line(to: NSPoint(x: well.minX + 32, y: wellBottom))
    band.appendArc(
        from: NSPoint(x: well.minX, y: wellBottom),
        to: NSPoint(x: well.minX, y: wellBottom + 32),
        radius: 32
    )
    band.close()
    color(0x7A7A83, 0.92).setFill()
    band.fill()

    color(0xFFFFFF, 0.10).setStroke()
    path.lineWidth = 1
    path.stroke()
}

// Arrow between the wells.
let arrowY = fromTop(wellCenterYFromTop)
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 272, y: arrowY))
shaft.line(to: NSPoint(x: 376, y: arrowY))
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.setLineDash([0.1, 12], count: 2, phase: 0)
color(0xFFFFFF, 0.35).setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 377, y: arrowY + 11))
head.line(to: NSPoint(x: 392, y: arrowY))
head.line(to: NSPoint(x: 377, y: arrowY - 11))
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
color(0xFFFFFF, 0.35).setStroke()
head.stroke()

drawCenteredText("Drag WinterVoice into Applications", size: 13.5, weight: .medium, alpha: 0.55, topY: 320)
drawCenteredText("Speak anywhere. It types for you.", size: 11.5, weight: .regular, alpha: 0.28, topY: 344)

NSGraphicsContext.restoreGraphicsState()

// The logical (point) size must be stamped so Finder renders the 2x
// pixels at 660x400 instead of doubling the window.
rep.size = pointSize
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outputURL)
print("wrote \(outputURL.path)")
