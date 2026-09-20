import AppKit
let path = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.11, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 50,y: 50,width: 924,height: 924),xRadius: 210,yRadius: 210).fill()
NSColor(calibratedRed: 0.88,green: 0.95,blue: 0.64,alpha: 1).setStroke()
let wand = NSBezierPath(); wand.lineWidth = 94; wand.lineCapStyle = .round
wand.move(to: NSPoint(x: 285,y: 285));wand.line(to: NSPoint(x: 630,y: 630));wand.stroke()
func star(_ x: CGFloat,_ y: CGFloat,_ radius: CGFloat) {
 let p=NSBezierPath();let points=[NSPoint(x:x,y:y+radius),NSPoint(x:x+radius/4,y:y+radius/4),NSPoint(x:x+radius,y:y),NSPoint(x:x+radius/4,y:y-radius/4),NSPoint(x:x,y:y-radius),NSPoint(x:x-radius/4,y:y-radius/4),NSPoint(x:x-radius,y:y),NSPoint(x:x-radius/4,y:y+radius/4)]
 p.move(to:points[0]); for point in points.dropFirst(){p.line(to:point)};p.close()
 NSColor(calibratedRed:0.88,green:0.95,blue:0.64,alpha:1).setFill();p.fill()
}
star(650,790,120);star(800,555,78)
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
