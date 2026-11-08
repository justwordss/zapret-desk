import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let folder = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
 let colorSpace = CGColorSpaceCreateDeviceRGB()
 let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 let rounded = CGPath(roundedRect:CGRect(x:36,y:36,width:952,height:952),cornerWidth:208,cornerHeight:208,transform:nil)
 ctx.addPath(rounded);ctx.clip()
 let colors = [CGColor(red:0.10,green:0.16,blue:0.23,alpha:1),CGColor(red:0.035,green:0.055,blue:0.09,alpha:1)] as CFArray
 ctx.drawLinearGradient(CGGradient(colorsSpace:colorSpace,colors:colors,locations:[0,1])!,start:CGPoint(x:100,y:980),end:CGPoint(x:850,y:0),options:[])
 let shield = CGMutablePath();shield.move(to:CGPoint(x:512,y:842));shield.addLine(to:CGPoint(x:798,y:716));shield.addLine(to:CGPoint(x:774,y:432));shield.addCurve(to:CGPoint(x:512,y:177),control1:CGPoint(x:758,y:305),control2:CGPoint(x:620,y:217));shield.addCurve(to:CGPoint(x:250,y:432),control1:CGPoint(x:404,y:217),control2:CGPoint(x:266,y:305));shield.addLine(to:CGPoint(x:226,y:716));shield.closeSubpath()
 ctx.saveGState();ctx.addPath(shield);ctx.clip()
 let mint = [CGColor(red:0.25,green:0.99,blue:0.79,alpha:1),CGColor(red:0.015,green:0.64,blue:0.64,alpha:1)] as CFArray
 ctx.drawLinearGradient(CGGradient(colorsSpace:colorSpace,colors:mint,locations:[0,1])!,start:CGPoint(x:240,y:800),end:CGPoint(x:800,y:220),options:[])
 ctx.restoreGState()
 ctx.setStrokeColor(CGColor(red:0.04,green:0.12,blue:0.17,alpha:1));ctx.setLineWidth(76);ctx.setLineJoin(.round);ctx.setLineCap(.round)
 ctx.move(to:CGPoint(x:382,y:649));ctx.addLine(to:CGPoint(x:641,y:649));ctx.addLine(to:CGPoint(x:383,y:391));ctx.addLine(to:CGPoint(x:642,y:391));ctx.strokePath()
 let image = ctx.makeImage()!
 let names:[String]
 switch size {case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"]}
 for name in names {let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(dest,image,nil);CGImageDestinationFinalize(dest)}
}
