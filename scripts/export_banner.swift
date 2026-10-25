import Foundation
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Vector wordmark: outlined glyphs render identically on GitHub without web fonts.
let font = CTFontCreateWithName("AvenirNext-DemiBold" as CFString, 76, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Remio", attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): CGColor(gray: 240.0 / 255, alpha: 1)]))
var paths = ""
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    for index in 0..<count {
        guard let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
        var commands = ""
        func point(_ p: CGPoint) -> String { String(format: "%.3f %.3f", Double(p.x + positions[index].x), Double(p.y)) }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: commands += "M \(point(e.points[0])) "
            case .addLineToPoint: commands += "L \(point(e.points[0])) "
            case .addQuadCurveToPoint: commands += "Q \(point(e.points[0])) \(point(e.points[1])) "
            case .addCurveToPoint: commands += "C \(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2])) "
            case .closeSubpath: commands += "Z "
            @unknown default: break
            }
        }
        paths += "<path d=\"\(commands)\"/>\n"
    }
}
let logo = try String(contentsOfFile: "design/identity/pulse/logo.svg", encoding: .utf8)
let content = logo.replacingOccurrences(of: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\">", with: "").replacingOccurrences(of: "</svg>", with: "")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="260" viewBox="0 0 1200 260" role="img" aria-labelledby="title">
<title id="title">Remio</title>
<rect width="1200" height="260" rx="24" fill="#121212"/>
<g transform="translate(447 97) scale(.12) translate(-306 -252)">\(content)</g>
<g fill="#F0F0F0" transform="translate(526 160) scale(1 -1)">\(paths)</g>
</svg>
"""
try svg.write(toFile: "design/identity/banner.svg", atomically: true, encoding: .utf8)

// PNG companion for previews and clients that do not render SVG.
let context = CGContext(data: nil, width: 2400, height: 520, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: 2, y: 2)
context.setFillColor(CGColor(gray: 18.0 / 255, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1200, height: 260), cornerWidth: 24, cornerHeight: 24, transform: nil))
context.fillPath()
let markSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: "design/identity/pulse/logo.png") as CFURL, nil)!
let mark = CGImageSourceCreateImageAtIndex(markSource, 0, nil)!
context.draw(mark, in: CGRect(x: 447 - 306 * 0.12, y: 260 - (97 - 252 * 0.12) - 1024 * 0.12, width: 1024 * 0.12, height: 1024 * 0.12))
context.setFillColor(CGColor(gray: 240.0 / 255, alpha: 1))
context.textPosition = CGPoint(x: 526, y: 100)
CTLineDraw(line, context)
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "design/identity/banner.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
