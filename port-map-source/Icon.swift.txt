import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                       bytesPerRow: 4096, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}
let background = rounded(94, 94, 836, 836, 190)
canvas.saveGState()
canvas.addPath(background)
canvas.clip()
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: [color(0.075, 0.19, 0.31), color(0.15, 0.36, 0.52)] as CFArray,
                          locations: [0, 1])!
canvas.drawLinearGradient(gradient, start: .init(x: 100, y: 100), end: .init(x: 910, y: 910), options: [])
canvas.restoreGState()

canvas.setStrokeColor(color(0.52, 0.85, 0.96))
canvas.setLineWidth(25)
canvas.setLineJoin(.round)
canvas.setLineCap(.round)
canvas.move(to: .init(x: 512, y: 550))
canvas.addLine(to: .init(x: 512, y: 427))
canvas.move(to: .init(x: 300, y: 360))
canvas.addLine(to: .init(x: 300, y: 427))
canvas.addLine(to: .init(x: 724, y: 427))
canvas.addLine(to: .init(x: 724, y: 360))
canvas.strokePath()

canvas.setFillColor(color(0.9, 0.97, 1))
canvas.addPath(rounded(292, 535, 440, 187, 49))
canvas.fillPath()
canvas.setFillColor(color(0.11, 0.29, 0.43))
for x in [367.0, 477.0, 587.0] {
    canvas.addPath(rounded(x, 606, 70, 38, 18))
    canvas.fillPath()
}
canvas.setFillColor(color(0.9, 0.97, 1))
for x in [249.0, 673.0] {
    canvas.addPath(rounded(x, 292, 102, 73, 23))
    canvas.fillPath()
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, canvas.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
