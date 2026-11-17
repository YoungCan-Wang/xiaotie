import AppKit
import ImageIO

enum ImageUtil {
    struct Saved {
        let name: String
        let width: Int
        let height: Int
    }

    /// 把剪贴板里的图片存成 PNG 文件，返回文件名和尺寸
    static func savePNG(data: Data, alreadyPNG: Bool, to dir: URL) -> Saved? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let name = UUID().uuidString + ".png"
        let url = dir.appendingPathComponent(name)

        if alreadyPNG {
            let size = pixelSize(of: source)
            do { try data.write(to: url) } catch { return nil }
            return Saved(name: name, width: size.0, height: size.1)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Saved(name: name, width: cgImage.width, height: cgImage.height)
    }

    static func pixelSize(of source: CGImageSource) -> (Int, Int) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return (0, 0) }
        let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        return (w, h)
    }
}

/// 缩略图缓存，避免每次滚动都重新解码大图
final class ImageCache {
    static let shared = ImageCache()
    static let sizes = [40, 96, 900]

    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for url: URL, maxPixel: Int) -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }

    func evict(_ url: URL) {
        for px in ImageCache.sizes {
            cache.removeObject(forKey: "\(url.path)#\(px)" as NSString)
        }
    }
}
