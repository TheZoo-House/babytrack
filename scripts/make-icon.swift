import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("app/Babytrack/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let size = NSSize(width: 1024, height: 1024)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
/// A small sun nested in a moon marks day-and-night care.
let ink = NSColor(calibratedRed: 36 / 255, green: 38 / 255, blue: 60 / 255, alpha: 1)
ink.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(calibratedRed: 187 / 255, green: 180 / 255, blue: 235 / 255, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 200, y: 190, width: 600, height: 600)).fill()
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: 375, y: 330, width: 535, height: 535)).fill()
NSColor(calibratedRed: 244 / 255, green: 197 / 255, blue: 110 / 255, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 282, y: 488, width: 214, height: 214)).fill()
NSColor(calibratedRed: 149 / 255, green: 204 / 255, blue: 232 / 255, alpha: 1).setFill()
let star = NSBezierPath()
star.move(to: NSPoint(x: 736, y: 752))
star.curve(to: NSPoint(x: 795, y: 693), controlPoint1: NSPoint(x: 746, y: 706), controlPoint2: NSPoint(x: 749, y: 703))
star.curve(to: NSPoint(x: 736, y: 634), controlPoint1: NSPoint(x: 749, y: 683), controlPoint2: NSPoint(x: 746, y: 680))
star.curve(to: NSPoint(x: 677, y: 693), controlPoint1: NSPoint(x: 726, y: 680), controlPoint2: NSPoint(x: 723, y: 683))
star.curve(to: NSPoint(x: 736, y: 752), controlPoint1: NSPoint(x: 723, y: 703), controlPoint2: NSPoint(x: 726, y: 706))
star.close(); star.fill()
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
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
