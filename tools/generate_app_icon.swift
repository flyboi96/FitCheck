import CoreGraphics
import Foundation
import ImageIO

private struct IconSlot {
    let filename: String
    let pixels: Int
}

private let slots = [
    IconSlot(filename: "Icon-20@2x.png", pixels: 40),
    IconSlot(filename: "Icon-20@3x.png", pixels: 60),
    IconSlot(filename: "Icon-29@2x.png", pixels: 58),
    IconSlot(filename: "Icon-29@3x.png", pixels: 87),
    IconSlot(filename: "Icon-40@2x.png", pixels: 80),
    IconSlot(filename: "Icon-40@3x.png", pixels: 120),
    IconSlot(filename: "Icon-60@2x.png", pixels: 120),
    IconSlot(filename: "Icon-60@3x.png", pixels: 180),
    IconSlot(filename: "Icon-1024.png", pixels: 1024)
]

private let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("FitCheck/Assets.xcassets/AppIcon.appiconset")

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func drawLine(
    in context: CGContext,
    points: [CGPoint],
    stroke: CGColor,
    width: CGFloat,
    cap: CGLineCap = .round,
    join: CGLineJoin = .round
) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
        context.addLine(to: point)
    }
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.setLineCap(cap)
    context.setLineJoin(join)
    context.strokePath()
}

private func makeContext(size: Int) throws -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = size * 4
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.coderInvalidValue)
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    return context
}

private func drawIcon(size: Int) throws -> CGImage {
    let context = try makeContext(size: size)
    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)

    let fullRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0x0f302d),
            color(0x123b33),
            color(0x182f4f)
        ] as CFArray,
        locations: [0, 0.56, 1]
    )!

    context.drawLinearGradient(
        background,
        start: CGPoint(x: 40, y: 40),
        end: CGPoint(x: 984, y: 984),
        options: []
    )

    context.saveGState()
    context.clip(to: fullRect)
    context.setStrokeColor(color(0xf6efe4, alpha: 0.055))
    context.setLineWidth(5)
    for offset in stride(from: -960, through: 1024, by: 64) {
        context.move(to: CGPoint(x: offset, y: 1024))
        context.addLine(to: CGPoint(x: offset + 1024, y: 0))
        context.strokePath()
    }
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 28), blur: 38, color: color(0x061312, alpha: 0.36))

    let hook = CGMutablePath()
    hook.move(to: CGPoint(x: 512, y: 342))
    hook.addLine(to: CGPoint(x: 512, y: 286))
    hook.addCurve(
        to: CGPoint(x: 606, y: 212),
        control1: CGPoint(x: 512, y: 224),
        control2: CGPoint(x: 574, y: 174)
    )
    hook.addCurve(
        to: CGPoint(x: 522, y: 298),
        control1: CGPoint(x: 650, y: 256),
        control2: CGPoint(x: 590, y: 306)
    )

    context.addPath(hook)
    context.setStrokeColor(color(0xf5efe4))
    context.setLineWidth(66)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    drawLine(
        in: context,
        points: [
            CGPoint(x: 512, y: 344),
            CGPoint(x: 248, y: 594),
            CGPoint(x: 236, y: 650),
            CGPoint(x: 784, y: 650),
            CGPoint(x: 768, y: 590),
            CGPoint(x: 512, y: 344)
        ],
        stroke: color(0xf5efe4),
        width: 64
    )

    drawLine(
        in: context,
        points: [
            CGPoint(x: 376, y: 566),
            CGPoint(x: 492, y: 684),
            CGPoint(x: 754, y: 410)
        ],
        stroke: color(0x58e0b3),
        width: 88
    )
    context.restoreGState()

    drawLine(
        in: context,
        points: [
            CGPoint(x: 376, y: 566),
            CGPoint(x: 492, y: 684),
            CGPoint(x: 754, y: 410)
        ],
        stroke: color(0xcff8e7, alpha: 0.55),
        width: 28
    )

    let tagRect = CGRect(x: 688, y: 600, width: 112, height: 136)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 20, color: color(0x061312, alpha: 0.24))
    let tagPath = CGPath(roundedRect: tagRect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    context.addPath(tagPath)
    context.setFillColor(color(0xd9644a))
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(color(0xf5efe4, alpha: 0.72))
    context.setLineWidth(7)
    context.stroke(CGRect(x: 720, y: 626, width: 48, height: 0))
    context.stroke(CGRect(x: 720, y: 656, width: 48, height: 0))

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw CocoaError(.fileWriteUnknown)
    }
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    let image = try drawIcon(size: slot.pixels)
    try writePNG(image, to: outputDirectory.appendingPathComponent(slot.filename))
}

print("Generated \(slots.count) FitCheck app icon PNGs.")
