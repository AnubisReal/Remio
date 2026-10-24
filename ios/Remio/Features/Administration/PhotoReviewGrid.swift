import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct PhotoReviewGrid: View {
    var photos: [PhotosPickerItem] = []
    var files: [URL] = []
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
            ForEach(photos.indices, id: \.self) { index in
                PhotoReviewThumbnail(item: photos[index])
                    .id(photos[index].itemIdentifier ?? String(index))
            }
            ForEach(files, id: \.self) { url in PhotoReviewThumbnail(url: url) }
        }.padding(.vertical, 6)
    }
}

private struct PhotoReviewThumbnail: View {
    var item: PhotosPickerItem?
    var url: URL?
    @State private var thumbnail: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .frame(height: 86).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(url?.lastPathComponent ?? String(localized: "Imagen seleccionada"))
        .task {
            do {
                let data: Data
                if let url {
                    data = try await Task.detached { try ImageTransfer.read(url) }.value
                } else if let item, let loaded = try await item.loadTransferable(type: Data.self) { data = loaded }
                else { throw ADBToolError.invalidData }
                let result = try await Task.detached { try ImageTransfer.thumbnail(data) }.value
                guard !Task.isCancelled else { return }
                thumbnail = UIImage(cgImage: result)
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

enum ImageTransfer {
    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= ADBTools.limit else { throw ADBToolError.tooLarge }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func validate(_ data: Data, suffix: String) throws {
        guard data.count > 0, data.count <= ADBTools.limit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source),
              let declared = UTType(filenameExtension: suffix), let actual = UTType(type as String), actual.conforms(to: declared) || declared.conforms(to: actual) else {
            throw ADBToolError.refused(String(localized: "El archivo no es una imagen válida o su extensión no coincide."))
        }
    }

    static func thumbnail(_ data: Data) throws -> CGImage {
        guard data.count <= 32 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ADBToolError.invalidData }
        return image
    }
}
