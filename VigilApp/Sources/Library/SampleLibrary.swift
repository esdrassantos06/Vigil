import Foundation
import Observation

struct Sample: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    let fileName: String
}

@MainActor
@Observable
final class SampleLibrary {
    private(set) var samples: [Sample] = []

    @ObservationIgnored private let defaultsKey = "userSamples"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Samples", isDirectory: true)
    }

    func url(for sample: Sample) -> URL {
        Self.directory.appendingPathComponent(sample.fileName)
    }

    /// Copies while the security scope is open, which is why a read-only entitlement is enough.
    @discardableResult
    func importFile(from source: URL) throws -> Sample {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard scoped || source.isFileURL else { throw LibraryError.accessDenied(source.lastPathComponent) }

        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)

        let sample = Sample(
            id: UUID(),
            displayName: destination.deletingPathExtension().lastPathComponent,
            fileName: destination.lastPathComponent
        )
        samples.append(sample)
        persist()
        return sample
    }

    func rename(_ sample: Sample, to name: String) {
        guard let index = samples.firstIndex(where: { $0.id == sample.id }) else { return }
        samples[index].displayName = name
        persist()
    }

    func delete(_ sample: Sample) {
        try? FileManager.default.removeItem(at: url(for: sample))
        samples.removeAll { $0.id == sample.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Sample].self, from: data)
        else { return }
        samples = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private static func uniqueURL(for name: String) -> URL {
        var candidate = directory.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            suffix += 1
        }
        return candidate
    }
}

enum LibraryError: VigilError {
    case accessDenied(String)

    var messageKey: String.LocalizationValue {
        switch self {
        case .accessDenied(let name):
            "Não foi possível ler \(name). Se estiver no iCloud, baixe o arquivo antes de importar."
        }
    }
}
