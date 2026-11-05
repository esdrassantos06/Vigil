import Foundation
#if os(macOS)
import CoreAudio
#endif

/// An output the user can pick in Settings, keyed by its persistent UID rather than the device
/// ID, which changes between boots and replugs.
struct OutputDevice: Identifiable, Hashable, Sendable {
    let uid: String
    let name: String

    var id: String { uid }
}

/// Buffer and output-device helpers over CoreAudio.
enum AudioOutput {
    /// Buffer sizes offered in Settings. The device may accept only part of this range.
    static let bufferChoices = [32, 64, 128, 256, 512, 1024]

    static func milliseconds(frames: Int, sampleRate: Double) -> Double {
        guard sampleRate > 0 else { return 0 }
        return Double(frames) / sampleRate * 1_000
    }

    static func clamp(_ frames: Int, to range: ClosedRange<Int>) -> Int {
        min(max(frames, range.lowerBound), range.upperBound)
    }

    #if os(macOS)
    /// Every device with at least one output stream, in the order CoreAudio lists them.
    static func devices() -> [OutputDevice] {
        allDeviceIDs().compactMap { id in
            guard hasOutput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName), !name.isEmpty
            else { return nil }
            return OutputDevice(uid: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { hasOutput($0) && string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func defaultOutputID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &id),
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func bufferRange(of device: AudioDeviceID) -> ClosedRange<Int>? {
        var range = AudioValueRange()
        guard read(device, kAudioDevicePropertyBufferFrameSizeRange, into: &range) else { return nil }
        return Int(range.mMinimum)...Int(range.mMaximum)
    }

    static func bufferFrames(of device: AudioDeviceID) -> Int? {
        var frames = UInt32(0)
        guard read(device, kAudioDevicePropertyBufferFrameSize, into: &frames) else { return nil }
        return Int(frames)
    }

    static func nominalSampleRate(of device: AudioDeviceID) -> Double? {
        var rate = Float64(0)
        guard read(device, kAudioDevicePropertyNominalSampleRate, into: &rate) else { return nil }
        return rate
    }

    /// - Returns: false when the device refused the size.
    @discardableResult
    static func setBufferFrames(_ frames: Int, on device: AudioDeviceID) -> Bool {
        var address = globalAddress(kAudioDevicePropertyBufferFrameSize)
        var value = UInt32(frames)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                into value: inout T) -> Bool {
        var address = globalAddress(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
    #endif
}

/// The buffer the hardware is actually running, read back after asking for one.
struct ActiveBuffer: Equatable, Sendable {
    let frames: Int
    let sampleRate: Double

    var milliseconds: Double { AudioOutput.milliseconds(frames: frames, sampleRate: sampleRate) }
}

enum OutputError: VigilError {
    case deviceMissing
    case deviceRefused

    var messageKey: String.LocalizationValue {
        switch self {
        case .deviceMissing: "A saída escolhida não está conectada. Voltando para a saída do sistema."
        case .deviceRefused: "Não foi possível usar essa saída de áudio."
        }
    }
}
