import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination,withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: pixels,pixelsHigh: pixels,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let outer = NSBezierPath(roundedRect: NSRect(x: p*0.06,y: p*0.06,width: p*0.88,height: p*0.88),xRadius: p*0.20,yRadius: p*0.20)
        NSGradient(starting: NSColor(calibratedRed: 0.50,green: 0.41,blue: 0.93,alpha: 1),ending: NSColor(calibratedRed: 0.33,green: 0.24,blue: 0.73,alpha: 1))!.draw(in: outer,angle: -90)
        let back = NSBezierPath(roundedRect: NSRect(x: p*0.24,y: p*0.37,width: p*0.40,height: p*0.40),xRadius: p*0.07,yRadius: p*0.07)
        NSColor.white.withAlphaComponent(0.43).setStroke(); back.lineWidth = max(p*0.045,1); back.stroke()
        let front = NSBezierPath(roundedRect: NSRect(x: p*0.37,y: p*0.23,width: p*0.40,height: p*0.40),xRadius: p*0.07,yRadius: p*0.07)
        NSColor.white.setStroke(); front.lineWidth = max(p*0.045,1); front.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png,properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}
