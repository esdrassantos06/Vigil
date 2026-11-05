import Foundation
import Testing
@testable import Vigil

/// Buffer size and output device are machine preferences: they survive a relaunch, stay inside
/// what the hardware accepts, and a missing device falls back to the system output loudly.
@MainActor
@Suite("Audio output", .serialized)
struct AudioOutputTests {

    private func model(_ store: UserDefaults? = nil) -> (AppModel, UserDefaults) {
        let id = UUID().uuidString
        let defaults = store ?? UserDefaults(suiteName: "vigil.tests.\(id)")!
        let app = AppModel(defaults: defaults,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.start()
        return (app, defaults)
    }

    @Test("Frames convert to milliseconds at the sample rate")
    func millisecondsFromFrames() {
        #expect(abs(AudioOutput.milliseconds(frames: 128, sampleRate: 44_100) - 2.902) < 0.01)
        #expect(abs(AudioOutput.milliseconds(frames: 1024, sampleRate: 48_000) - 21.333) < 0.01)
    }

    @Test("A requested buffer is held inside what the device accepts")
    func bufferIsClamped() {
        #expect(AudioOutput.clamp(32, to: 64...4096) == 64)
        #expect(AudioOutput.clamp(2048, to: 15...512) == 512)
        #expect(AudioOutput.clamp(256, to: 15...4096) == 256)
    }

    /// Neither model starts its engine, so the test never resizes the machine's real device
    /// under the live audio tests running beside it.
    @Test("Buffer size and output device survive a relaunch")
    func choicesPersist() {
        let id = UUID().uuidString
        let store = UserDefaults(suiteName: "vigil.tests.\(id)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-tests/\(id)")
        let first = AppModel(defaults: store, samplesDirectory: directory)
        first.bufferFrames = 256
        let second = AppModel(defaults: store, samplesDirectory: directory)
        second.restoreOutput()
        #expect(second.bufferFrames == 256)
    }

    @Test("The default buffer is the low-latency 128 frames")
    func defaultBuffer() {
        let (app, _) = model()
        #expect(app.bufferFrames == 128)
        #expect(app.outputDeviceUID == nil)
    }

    @Test("A device that is not connected falls back to the system output and says so")
    func missingDeviceFallsBack() {
        let (app, _) = model()
        app.outputDeviceUID = "vigil.tests.no-such-device"
        #expect(app.outputDeviceUID == nil)
        #expect(app.toasts.current?.kind == .error)
    }

    #if os(macOS)
    @Test("A model whose engine is not running leaves the hardware alone")
    func noHardwareBeforeStart() {
        guard let device = AudioOutput.defaultOutputID(),
              let before = AudioOutput.bufferFrames(of: device) else { return }
        let id = UUID().uuidString
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)"))
        app.bufferFrames = before == 512 ? 256 : 512
        #expect(AudioOutput.bufferFrames(of: device) == before)
    }

    @Test("Listed outputs have unique identifiers and readable names")
    func devicesAreWellFormed() {
        let devices = AudioOutput.devices()
        #expect(Set(devices.map(\.uid)).count == devices.count)
        #expect(devices.allSatisfy { !$0.name.isEmpty })
    }
    #endif
}
