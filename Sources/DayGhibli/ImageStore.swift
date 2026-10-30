import Foundation
import ImageIO
import WallpaperCore

protocol WallpaperDownloading: Sendable {
    func download(_ image: Wallpaper) async throws -> URL
    func prune(keeping urls: Set<URL>) async throws
}

extension WallpaperDownloading {
    // Existing download-only test doubles do not own a cache to prune.
    func prune(keeping urls: Set<URL>) async throws {}
}

actor ImageStore: WallpaperDownloading {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    // This is called only by the explicit download-and-change action.
    func download(_ image: Wallpaper) async throws -> URL {
        guard image.url.scheme == "https", image.url.host == "www.ghibli.jp",
              image.url.path.hasPrefix("/gallery/"),
              image.id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw ImageError.invalidSource
        }
        var request = URLRequest(url: image.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 30
        request.setValue("DayGhibli/1.0", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "www.ghibli.jp" else {
            throw ImageError.downloadFailed
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20_000_000, Self.isImage(at: temporary) else {
            throw ImageError.invalidImage
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Unique stable names avoid overwriting a file macOS is currently displaying.
        let local = directory.appendingPathComponent("\(image.id)-\(UUID().uuidString).jpg")
        try FileManager.default.moveItem(at: temporary, to: local)
        return local
    }

    func prune(keeping urls: Set<URL>) async throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: directory.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }

        // Do not traverse a cache root that was replaced with a symbolic link.
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { return }
        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let retained = Set(urls.filter(\.isFileURL).map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        })
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [])
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }

        for file in files where file.pathExtension.lowercased() == "jpg" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink == false, values.isRegularFile == true else { continue }
            let normalized = file.standardizedFileURL.resolvingSymlinksInPath()
            guard normalized.deletingLastPathComponent().path == normalizedDirectory.path,
                  !retained.contains(normalized) else { continue }
            try fileManager.removeItem(at: file)
        }
    }

    static func isImage(at url: URL) -> Bool {
        guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
              bytes.starts(with: [0xFF, 0xD8]), bytes.suffix(2).elementsEqual([0xFF, 0xD9]),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              width * height <= 100_000_000 else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }
}

enum ImageError: LocalizedError {
    case invalidSource, downloadFailed, invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidSource: "图片来源无效。"
        case .downloadFailed: "暂时无法下载图片，请检查网络后重试。"
        case .invalidImage: "下载的文件不是有效图片，已保留原壁纸。"
        }
    }
}
