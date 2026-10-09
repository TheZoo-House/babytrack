import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("app/Babytrack/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.89, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(calibratedRed: 0.24, green: 0.39, blue: 0.33, alpha: 1).setStroke()
let stem = NSBezierPath(); stem.move(to: NSPoint(x: 510, y: 260)); stem.curve(
    to: NSPoint(x: 530, y: 570),
    controlPoint1: NSPoint(x: 465, y: 365),
    controlPoint2: NSPoint(x: 565, y: 465)
); stem.lineWidth = 28; stem.lineCapStyle = .round; stem.stroke()
NSColor(calibratedRed: 0.24, green: 0.39, blue: 0.33, alpha: 1).setFill()
let leaf = NSBezierPath(); leaf.move(to: NSPoint(x: 516, y: 478)); leaf.curve(
    to: NSPoint(x: 738, y: 727),
    controlPoint1: NSPoint(x: 495, y: 650),
    controlPoint2: NSPoint(x: 660, y: 735)
); leaf.curve(
    to: NSPoint(x: 516, y: 478),
    controlPoint1: NSPoint(x: 790, y: 550),
    controlPoint2: NSPoint(x: 652, y: 473)
); leaf.fill()
NSColor(calibratedRed: 0.62, green: 0.73, blue: 0.57, alpha: 1).setFill()
let other = NSBezierPath(); other.move(to: NSPoint(x: 505, y: 427)); other.curve(
    to: NSPoint(x: 280, y: 652),
    controlPoint1: NSPoint(x: 490, y: 591),
    controlPoint2: NSPoint(x: 365, y: 660)
); other.curve(
    to: NSPoint(x: 505, y: 427),
    controlPoint1: NSPoint(x: 247, y: 475),
    controlPoint2: NSPoint(x: 351, y: 406)
); other.fill()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("Icon.png"))
let contents = """
{"images":[{"filename":"Icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(
    to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
