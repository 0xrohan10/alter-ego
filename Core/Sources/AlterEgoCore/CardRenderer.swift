import Foundation
#if canImport(CoreGraphics) && canImport(CoreText) && canImport(ImageIO)
import CoreGraphics
import CoreText
import ImageIO
#endif

public enum CardRenderer {
    public static let width = 1200
    public static let height = 1776
    public static let widthMM = 100.0
    public static let heightMM = 148.0

    public static func render(name: String, title: String, number: Int, artwork: Data, directory: URL) throws {
        #if canImport(CoreGraphics) && canImport(CoreText) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(artwork as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw AlterEgoError.invalid("Could not decode artwork or allocate card canvas.") }
        let navy = color(0x101D2B), cream = color(0xF4E9D2), brass = color(0xD6B87D), ink = color(0x162635), muted = color(0x607078)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: CGFloat(height) - y - h, width: w, height: h) }
        func fill(_ r: CGRect, _ c: CGColor) { ctx.setFillColor(c); ctx.fill(r) }
        func stroke(_ r: CGRect, _ c: CGColor, _ line: CGFloat) { ctx.setStrokeColor(c); ctx.setLineWidth(line); ctx.stroke(r) }
        fill(rect(0,0,1200,1776), navy)
        stroke(rect(42,42,1116,1692), brass, 2)
        // Masthead: a readable, non-AI typographic identity.
        line("SOUTHWIND LABS   /   HOLIDAY 2026", y: 68, maxWidth: 1050, size: 30, font: "Menlo-Bold", color: brass, in: ctx)
        let art = rect(70,128,1060,1260)
        fill(art, cream)
        ctx.saveGState(); ctx.clip(to: art); ctx.interpolationQuality = .high
        let scale = max(art.width / CGFloat(image.width), art.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        // Slight upper bias keeps faces in frame when a portrait is cropped.
        ctx.draw(image, in: CGRect(x: art.midX-w/2, y: art.maxY-h+max(0,h-art.height)*0.25, width: w, height: h))
        ctx.restoreGState()
        stroke(art, brass, 2)
        fill(rect(70,1388,1060,318), cream)
        fill(rect(70,1388,1060,10), brass)
        line("ALTER EGO  /  CHARACTER DOSSIER", y: 1420, maxWidth: 970, size: 24, font: "Menlo-Bold", color: muted, in: ctx)
        line(name.uppercased(), y: 1460, maxWidth: 970, size: 116, font: "HelveticaNeue-Bold", color: ink, in: ctx)
        line(title, y: 1581, maxWidth: 970, size: 45, font: "HelveticaNeue-Medium", color: ink, in: ctx)
        fill(rect(106,1648,988,2), brass)
        line(String(format: "EXPEDITION 026   ·   CREW NO. %03d", number), y: 1662, maxWidth: 980, size: 24, font: "Menlo-Bold", color: muted, in: ctx)
        guard let card = ctx.makeImage() else { throw AlterEgoError.invalid("Could not render card.") }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg as CFMutableData, "public.jpeg" as CFString, 1, nil) else { throw AlterEgoError.invalid("Could not encode JPEG.") }
        let dpi = Double(width) / (widthMM / 25.4)
        CGImageDestinationAddImage(destination, card, [kCGImageDestinationLossyCompressionQuality: 0.94, kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AlterEgoError.invalid("Could not finalize JPEG.") }
        // A PDF with an exact physical page size is useful for the wired fallback.
        let pdf = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: widthMM / 25.4 * 72, height: heightMM / 25.4 * 72)
        guard let consumer = CGDataConsumer(data: pdf as CFMutableData), let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw AlterEgoError.invalid("Could not allocate PDF.") }
        pdfContext.beginPDFPage(nil); pdfContext.draw(card, in: mediaBox); pdfContext.endPDFPage(); pdfContext.closePDF()
        try (pdf as Data).write(to: directory.appendingPathComponent("card.pdf"), options: .atomic)
        try (jpeg as Data).write(to: directory.appendingPathComponent("card.jpg"), options: .atomic)
        #else
        throw AlterEgoError.unsupported("Card rendering uses Core Graphics and requires macOS or iPadOS. The API and job-store tests run on Linux.")
        #endif
    }
    #if canImport(CoreGraphics) && canImport(CoreText) && canImport(ImageIO)
    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    private static func line(_ text: String, y: CGFloat, maxWidth: CGFloat, size: CGFloat, font: String, color: CGColor, in ctx: CGContext) {
        let safe = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        func make(_ fontSize: CGFloat) -> CTLine {
            let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, fontSize, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
            return CTLineCreateWithAttributedString(NSAttributedString(string: safe, attributes: attrs))
        }
        var line = make(size)
        var w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if w > maxWidth { line = make(size * maxWidth / w * 0.98); w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
        var asc: CGFloat = 0; _ = CTLineGetTypographicBounds(line, &asc, nil, nil)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: (CGFloat(width)-w)/2, y: CGFloat(height)-y-asc)
        CTLineDraw(line, ctx)
    }
    #endif
}
