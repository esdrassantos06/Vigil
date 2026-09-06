import AppKit
import CoreGraphics
import Foundation


let sizes = [16, 32, 64, 128, 256, 512, 1024]
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func flamePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 250))
    path.addCurve(to: CGPoint(x: 400, y: 512),
                  control1: CGPoint(x: 430, y: 360), control2: CGPoint(x: 400, y: 430))
    path.addCurve(to: CGPoint(x: 512, y: 742),
                  control1: CGPoint(x: 400, y: 612), control2: CGPoint(x: 460, y: 690))
    path.addCurve(to: CGPoint(x: 624, y: 512),
                  control1: CGPoint(x: 564, y: 690), control2: CGPoint(x: 624, y: 612))
    path.addCurve(to: CGPoint(x: 512, y: 250),
                  control1: CGPoint(x: 624, y: 430), control2: CGPoint(x: 594, y: 360))
    path.closeSubpath()
    return path
}

func innerPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 400))
    path.addCurve(to: CGPoint(x: 458, y: 558),
                  control1: CGPoint(x: 474, y: 462), control2: CGPoint(x: 458, y: 508))
    path.addCurve(to: CGPoint(x: 512, y: 680),
                  control1: CGPoint(x: 458, y: 616), control2: CGPoint(x: 486, y: 660))
    path.addCurve(to: CGPoint(x: 566, y: 558),
                  control1: CGPoint(x: 538, y: 660), control2: CGPoint(x: 566, y: 616))
    path.addCurve(to: CGPoint(x: 512, y: 400),
                  control1: CGPoint(x: 566, y: 508), control2: CGPoint(x: 550, y: 462))
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func render(size: Int) -> Data? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)

    let radius: CGFloat = 224
    let plate = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                       cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(plate)
    context.setFillColor(color(0x0A0A0A))
    context.fillPath()

    context.saveGState()
    if let glow = CGGradient(colorsSpace: space,
                             colors: [color(0xF4A437, 0.20), color(0xF4A437, 0)] as CFArray,
                             locations: [0, 1]) {
        let center = CGPoint(x: 512, y: 540)
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: 300,
                                   options: .drawsAfterEndLocation)
    }
    context.restoreGState()

    context.saveGState()
    context.addPath(flamePath())
    context.clip()
    if let flame = CGGradient(colorsSpace: space,
                              colors: [color(0xFFC978), color(0xE8901F)] as CFArray,
                              locations: [0, 1]) {
        context.drawLinearGradient(flame, start: CGPoint(x: 512, y: 250),
                                   end: CGPoint(x: 512, y: 742), options: [])
    }
    context.restoreGState()

    context.addPath(innerPath())
    context.setFillColor(color(0x0A0A0A, 0.55))
    context.fillPath()

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = render(size: size) else {
        FileHandle.standardError.write("falhou em \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: output).appendingPathComponent("icon-\(size).png")
    try data.write(to: url)
    print("\(url.lastPathComponent)")
}
