// Renders the app icon: two screens, the big one showing a timer ring.
// swift scripts/icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CGColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
                             CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let center = CGPoint(x: size / 2, y: size / 2)
let radius = 330.0
ctx.setLineWidth(84)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.setStrokeColor(CGColor(red: 1, green: 0.6, blue: 0, alpha: 1))
ctx.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.45, clockwise: true)
ctx.strokePath()

// Hand
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(56)
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x, y: center.y + 190))
ctx.strokePath()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - 50, y: center.y - 50, width: 100, height: 100))

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
