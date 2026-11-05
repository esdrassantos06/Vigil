import AVFoundation
import AudioToolbox
import Testing
@testable import Vigil

/// The suite starts live engines; the test scheme sets VIGIL_MUTE_OUTPUT so they stay silent
/// on the speakers while the taps before the output still measure the full signal.
@MainActor
@Suite("Muted output under tests", .serialized)
struct MutedOutputTests {

    #if os(macOS)
    @Test("With VIGIL_MUTE_OUTPUT set, a started graph sends nothing to the hardware")
    func outputIsMuted() throws {
        try #require(ProcessInfo.processInfo.environment["VIGIL_MUTE_OUTPUT"] == "1",
                     "the test scheme must set VIGIL_MUTE_OUTPUT=1")
        let graph = AudioGraph()
        try graph.start()
        defer { graph.engine.stop() }
        let unit = try #require(graph.engine.outputNode.audioUnit)
        var volume = AudioUnitParameterValue(1)
        #expect(AudioUnitGetParameter(unit, kHALOutputParam_Volume, kAudioUnitScope_Global, 0, &volume) == noErr)
        #expect(volume == 0)
    }
    #endif
}
