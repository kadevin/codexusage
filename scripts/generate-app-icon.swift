#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: generate-app-icon.swift <iconset-output-dir> <icns-output-file>\n".utf8))
    exit(64)
}

let iconsetURL = URL(fileURLWithPath: arguments[1])
let icnsURL = URL(fileURLWithPath: arguments[2])
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for iconFile in iconFiles {
    let rep = makeIcon(size: iconFile.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Failed to create \(iconFile.name)\n".utf8))
        exit(65)
    }
    try data.write(to: iconsetURL.appendingPathComponent(iconFile.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed with status \(process.terminationStatus)\n".utf8))
    exit(process.terminationStatus)
}

func makeIcon(size pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap representation")
    }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Unable to create graphics context")
    }
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.cgContext.scaleBy(x: size / 1024, y: size / 1024)
    context.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    return rep
}

func drawIcon() {
    drawBase()
    drawUsagePanel()
    drawTokenMeter()
    drawTrendBars()
}

func drawBase() {
    let baseRect = CGRect(x: 86, y: 86, width: 852, height: 852)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 204, yRadius: 204)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -28)
    shadow.shadowBlurRadius = 54
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    color("#0D1720").setFill()
    basePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()
    NSGradient(colors: [
        color("#0F2430"),
        color("#14505B"),
        color("#227A72")
    ])?.draw(in: basePath, angle: 315)

    color("#FFFFFF", alpha: 0.16).setFill()
    NSBezierPath(ovalIn: CGRect(x: 52, y: 718, width: 640, height: 260)).fill()
    color("#7EE7D3", alpha: 0.18).setFill()
    NSBezierPath(ovalIn: CGRect(x: 568, y: 102, width: 340, height: 310)).fill()
    NSGraphicsContext.restoreGraphicsState()

    color("#FFFFFF", alpha: 0.28).setStroke()
    basePath.lineWidth = 7
    basePath.stroke()
}

func drawUsagePanel() {
    let panelRect = CGRect(x: 204, y: 246, width: 616, height: 540)
    let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 76, yRadius: 76)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 34
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.set()
    color("#F8FBFF").setFill()
    panelPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    panelPath.addClip()
    NSGradient(colors: [
        color("#FFFFFF"),
        color("#E8F3F6")
    ])?.draw(in: panelPath, angle: 270)
    color("#D9E9EF", alpha: 0.92).setFill()
    roundedRect(x: 268, y: 650, width: 190, height: 22, radius: 11).fill()
    color("#C9DCE4", alpha: 0.9).setFill()
    roundedRect(x: 268, y: 610, width: 134, height: 16, radius: 8).fill()
    NSGraphicsContext.restoreGraphicsState()

    color("#CADBE3", alpha: 0.9).setStroke()
    panelPath.lineWidth = 4
    panelPath.stroke()
}

func drawTokenMeter() {
    color("#16A085", alpha: 0.15).setFill()
    NSBezierPath(ovalIn: CGRect(x: 578, y: 602, width: 128, height: 128)).fill()

    color("#128C7E").setStroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: 594, y: 618, width: 96, height: 96))
    ring.lineWidth = 18
    ring.stroke()

    color("#5AA7FF").setStroke()
    let accent = NSBezierPath()
    accent.appendArc(
        withCenter: NSPoint(x: 642, y: 666),
        radius: 48,
        startAngle: -28,
        endAngle: 88,
        clockwise: false
    )
    accent.lineCapStyle = .round
    accent.lineWidth = 18
    accent.stroke()

    color("#148376").setFill()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 650, y: 706))
    bolt.line(to: NSPoint(x: 616, y: 657))
    bolt.line(to: NSPoint(x: 644, y: 657))
    bolt.line(to: NSPoint(x: 629, y: 624))
    bolt.line(to: NSPoint(x: 682, y: 680))
    bolt.line(to: NSPoint(x: 653, y: 680))
    bolt.close()
    bolt.fill()

    color("#F4B84A").setStroke()
    let costToken = NSBezierPath(ovalIn: CGRect(x: 708, y: 610, width: 74, height: 74))
    costToken.lineWidth = 12
    costToken.stroke()
}

func drawTrendBars() {
    let baseline: CGFloat = 330
    let barWidth: CGFloat = 34
    let gap: CGFloat = 18
    let startX: CGFloat = 278
    let heights: [CGFloat] = [76, 132, 102, 182, 148, 246, 208, 304]

    for (index, height) in heights.enumerated() {
        let x = startX + CGFloat(index) * (barWidth + gap)
        let barColor = index == heights.indices.last ? color("#4F91FF") : color("#42C8B7")
        barColor.withAlphaComponent(index == heights.indices.last ? 1 : 0.82).setFill()
        roundedRect(x: x, y: baseline, width: barWidth, height: height, radius: 17).fill()
    }

    color("#AEBFC7", alpha: 0.46).setStroke()
    let axis = NSBezierPath()
    axis.move(to: NSPoint(x: 258, y: baseline))
    axis.line(to: NSPoint(x: 724, y: baseline))
    axis.lineWidth = 5
    axis.lineCapStyle = .round
    axis.stroke()

    color("#2C3D48", alpha: 0.78).setFill()
    roundedRect(x: 278, y: 544, width: 278, height: 20, radius: 10).fill()
    color("#4F91FF", alpha: 0.72).setFill()
    roundedRect(x: 278, y: 544, width: 194, height: 20, radius: 10).fill()

    color("#2C3D48", alpha: 0.48).setFill()
    roundedRect(x: 278, y: 504, width: 356, height: 14, radius: 7).fill()
    color("#42C8B7", alpha: 0.74).setFill()
    roundedRect(x: 278, y: 504, width: 270, height: 14, radius: 7).fill()
}

func roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: CGRect(x: x, y: y, width: width, height: height),
        xRadius: radius,
        yRadius: radius
    )
}

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
        return NSColor.black.withAlphaComponent(alpha)
    }

    let red = CGFloat((value >> 16) & 0xFF) / 255
    let green = CGFloat((value >> 8) & 0xFF) / 255
    let blue = CGFloat(value & 0xFF) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}
