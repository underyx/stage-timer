// Renders the app icon: a cream CRT set whose screen shows the timer's progress bar.
// swift scripts/icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Top-left origin, like the mockups this was designed against.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor {
    CGColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
}
let orange = rgb(255, 153, 0)

func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient {
    CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1])!
}

/// Fill `path` with a vertical gradient from `top` at the top edge of `rect` to `bottom` at its bottom.
func fillVertical(_ path: CGPath, in rect: CGRect, _ top: CGColor, _ bottom: CGColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(top, bottom), start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    ctx.restoreGState()
}

func rounded(_ rect: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A soft shadow of `path`, offset `dy` downwards: CoreGraphics has no blur, but shadows are blurred.
func softShadow(_ path: CGPath, dy: Double, blur: Double, alpha: Double) {
    ctx.saveGState()
    // Draw the shape itself 2048 px above the canvas so only its shadow lands on the icon. Shadow
    // offsets are in base space, where y points up, so bringing it back down is negative.
    ctx.translateBy(x: 0, y: -2048)
    ctx.setShadow(offset: CGSize(width: 0, height: -2048 - dy), blur: blur, color: rgb(0, 0, 0, alpha))
    ctx.setFillColor(rgb(0, 0, 0))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

/// The CRT glass: a superellipse (|x|^n + |y|^n = 1) so the edges bow outward like a picture tube.
func barrel(_ rect: CGRect, n: Double = 3.4) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
    for i in 0..<720 {
        let a = Double(i) / 2 * .pi / 180
        let c = cos(a), s = sin(a)
        let x = cx + rx * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + ry * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

// Background
ctx.drawLinearGradient(gradient(rgb(36, 36, 42), rgb(10, 10, 12)), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// Body: cream set with a bevelled edge, sitting on two feet.
let body = CGRect(x: 96, y: 150, width: 832, height: 640)
let bodyPath = rounded(body, 110)
softShadow(bodyPath, dy: 60, blur: 30, alpha: 0.67)
fillVertical(bodyPath, in: body, rgb(240, 236, 226), rgb(206, 200, 186))
ctx.setLineWidth(4)
ctx.setStrokeColor(rgb(255, 255, 250, 0.47))
ctx.addPath(rounded(body.insetBy(dx: 3, dy: 3), 107))
ctx.strokePath()
ctx.setLineWidth(3)
ctx.setStrokeColor(rgb(120, 112, 98))
ctx.addPath(bodyPath)
ctx.strokePath()

for x in [236.0, 690.0] {
    ctx.setFillColor(rgb(140, 132, 118))
    ctx.addPath(rounded(CGRect(x: x, y: 780, width: 100, height: 66), 20))
    ctx.fillPath()
    ctx.setFillColor(rgb(178, 170, 156))
    ctx.addPath(rounded(CGRect(x: x + 4, y: 782, width: 92, height: 56), 18))
    ctx.fillPath()
}

// Bezel: a recessed dark frame around the glass.
let bezel = CGRect(x: 136, y: 192, width: 616, height: 556)
let bezelPath = rounded(bezel, 90)
softShadow(rounded(bezel.insetBy(dx: -4, dy: -2).offsetBy(dx: 0, dy: 8), 90), dy: 0, blur: 10, alpha: 0.43)
fillVertical(bezelPath, in: bezel, rgb(58, 54, 48), rgb(84, 80, 72))

// Screen
let screen = CGRect(x: 168, y: 224, width: 552, height: 492)
let glass = barrel(screen)
ctx.saveGState()
ctx.addPath(glass)
ctx.clip()
ctx.drawLinearGradient(gradient(rgb(46, 50, 56), rgb(14, 14, 18)), start: CGPoint(x: 0, y: screen.minY), end: CGPoint(x: 0, y: screen.maxY), options: [])
// Vignette: clear in the middle, darker towards the tube's edges.
ctx.drawRadialGradient(
    gradient(rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.75)),
    startCenter: CGPoint(x: screen.midX, y: screen.midY), startRadius: screen.width * 0.25,
    endCenter: CGPoint(x: screen.midX, y: screen.midY), endRadius: screen.width * 0.72, options: [.drawsAfterEndLocation])

// Progress bar: 68% of a dim track, glowing.
let barHeight = 78.0
let track = CGRect(x: screen.minX + 70, y: screen.midY - barHeight / 2, width: screen.width - 140, height: barHeight)
var fill = track
fill.size.width = track.width * 0.68
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 28, color: rgb(255, 153, 0, 0.47))
ctx.setFillColor(orange)
ctx.addPath(rounded(fill, barHeight / 2))
ctx.fillPath()
ctx.restoreGState()
ctx.setFillColor(rgb(70, 70, 78))
ctx.addPath(rounded(track, barHeight / 2))
ctx.fillPath()
ctx.setFillColor(orange)
ctx.addPath(rounded(fill, barHeight / 2))
ctx.fillPath()

// Scanlines
ctx.setStrokeColor(rgb(0, 0, 0, 0.165))
ctx.setLineWidth(2)
var y = screen.minY
while y < screen.maxY {
    ctx.move(to: CGPoint(x: screen.minX, y: y))
    ctx.addLine(to: CGPoint(x: screen.maxX, y: y))
    y += 6
}
ctx.strokePath()

// Glass highlight: a soft sweep across the top-left of the tube.
let sweep = CGRect(x: screen.minX - screen.width * 0.15, y: screen.minY - screen.height * 0.35,
                   width: screen.width * 0.9, height: screen.height * 0.77)
ctx.saveGState()
ctx.addEllipse(in: sweep)
ctx.clip()
ctx.drawRadialGradient(
    gradient(rgb(255, 255, 255, 0.3), rgb(255, 255, 255, 0)),
    startCenter: CGPoint(x: sweep.midX, y: sweep.midY), startRadius: 0,
    endCenter: CGPoint(x: sweep.midX, y: sweep.midY), endRadius: sweep.width / 2, options: [])
ctx.restoreGState()
ctx.restoreGState() // glass clip

// Control panel: two knobs and a speaker grille.
for cy in [300.0, 440.0] {
    let ring = CGRect(x: 792, y: cy - 48, width: 92, height: 92)
    softShadow(CGPath(ellipseIn: ring.offsetBy(dx: 0, dy: 6), transform: nil), dy: 0, blur: 8, alpha: 0.43)
    ctx.setFillColor(rgb(110, 104, 94))
    ctx.fillEllipse(in: ring)
    let cap = CGRect(x: 798, y: cy - 42, width: 80, height: 80)
    fillVertical(CGPath(ellipseIn: cap, transform: nil), in: cap, rgb(190, 184, 172), rgb(140, 134, 122))
    ctx.setStrokeColor(rgb(96, 90, 80))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: cap)
    ctx.setStrokeColor(rgb(58, 54, 48))
    ctx.setLineWidth(7)
    ctx.setLineCap(.butt)
    ctx.move(to: CGPoint(x: 838, y: cy - 32))
    ctx.addLine(to: CGPoint(x: 838, y: cy - 8))
    ctx.strokePath()
}
for i in 0..<6 {
    let y = 540.0 + Double(i) * 30
    ctx.setFillColor(rgb(150, 144, 132))
    ctx.addPath(rounded(CGRect(x: 796, y: y, width: 84, height: 13), 6))
    ctx.fillPath()
    ctx.setFillColor(rgb(120, 114, 102))
    ctx.addPath(rounded(CGRect(x: 796, y: y + 1, width: 84, height: 4), 2))
    ctx.fillPath()
}

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
