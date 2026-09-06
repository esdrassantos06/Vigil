import Foundation
import CoreMIDI
import Observation

enum MidiEvent: Sendable {
    case note(channel: Int, number: UInt8, velocity: UInt8)
    case control(channel: Int, number: UInt8, value: UInt8)

    var channel: Int {
        switch self {
        case .note(let channel, _, _), .control(let channel, _, _): channel
        }
    }
}

struct MidiSource: Identifiable, Hashable, Sendable {
    let id: MIDIUniqueID
    let endpoint: MIDIEndpointRef
    let name: String
}

/// Words per UMP message, indexed by the message type in the first nibble.
private let wordsPerMessage = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

@MainActor
@Observable
final class MidiEngine {
    private(set) var sources: [MidiSource] = []

    @ObservationIgnored var onEvent: ((MidiEvent) -> Void)?
    @ObservationIgnored var onSourcesChanged: (([String], [String]) -> Void)?
    @ObservationIgnored var disabled: Set<String> = [] { didSet { syncConnections() } }

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()
    @ObservationIgnored private var connected: Set<MIDIUniqueID> = []

    func start() throws {
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("Vigil" as CFString, &newClient) { @Sendable [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scan() }
            }
        }
        guard clientStatus == noErr else { throw MidiError.clientFailed }
        client = newClient

        var newPort = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "Vigil In" as CFString, ._1_0, &newPort
        ) { @Sendable [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard portStatus == noErr else { throw MidiError.portFailed }
        port = newPort

        scan(announce: false)
    }

    private func scan(announce: Bool = true) {
        var found: [MidiSource] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            found.append(
                MidiSource(id: uniqueID(of: endpoint), endpoint: endpoint, name: name(of: endpoint))
            )
        }

        let before = Set(sources.map(\.id))
        let after = Set(found.map(\.id))
        let added = found.filter { !before.contains($0.id) }.map(\.name)
        let removed = sources.filter { !after.contains($0.id) }.map(\.name)

        connected.formIntersection(after)
        sources = found
        syncConnections()

        if announce, !added.isEmpty || !removed.isEmpty {
            onSourcesChanged?(added, removed)
        }
    }

    private func syncConnections() {
        for source in sources {
            let wanted = !disabled.contains(source.name)
            let isConnected = connected.contains(source.id)
            guard wanted != isConnected else { continue }
            if wanted {
                guard MIDIPortConnectSource(port, source.endpoint, nil) == noErr else { continue }
                connected.insert(source.id)
            } else {
                MIDIPortDisconnectSource(port, source.endpoint)
                connected.remove(source.id)
            }
        }
    }

    private func uniqueID(of endpoint: MIDIEndpointRef) -> MIDIUniqueID {
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        return id
    }

    private func name(of endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr,
              let name = value?.takeRetainedValue()
        else { return "Entrada MIDI" }
        return name as String
    }

    /// Runs on the CoreMIDI thread. Delivery hops to main through `DispatchQueue`, which is
    /// FIFO; `Task` gives no ordering guarantee and notes and CCs must arrive in order.
    private nonisolated func receive(_ list: UnsafePointer<MIDIEventList>) {
        let base = UnsafeMutableRawPointer(mutating: list)
        let offset = MemoryLayout<MIDIEventList>.offset(of: \.packet) ?? 8
        var packet = base.advanced(by: offset).assumingMemoryBound(to: MIDIEventPacket.self)

        var events: [MidiEvent] = []
        for _ in 0..<Int(list.pointee.numPackets) {
            events.append(contentsOf: Self.events(in: packet.pointee))
            packet = MIDIEventPacketNext(packet)
        }
        guard !events.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for event in events { self.onEvent?(event) }
            }
        }
    }

    private nonisolated static func events(in packet: MIDIEventPacket) -> [MidiEvent] {
        withUnsafeBytes(of: packet.words) { raw in
            let words = raw.bindMemory(to: UInt32.self)
            let count = min(Int(packet.wordCount), words.count)
            var events: [MidiEvent] = []
            var index = 0

            while index < count {
                let word = words[index]
                let messageType = Int(word >> 28)
                index += wordsPerMessage[messageType]
                guard messageType == 0x2 else { continue }

                let status = (word >> 16) & 0xFF
                let channel = Int(status & 0x0F) + 1
                let data1 = UInt8((word >> 8) & 0x7F)
                let data2 = UInt8(word & 0x7F)

                switch status >> 4 {
                case 0x9 where data2 > 0:
                    events.append(.note(channel: channel, number: data1, velocity: data2))
                case 0xB: events.append(.control(channel: channel, number: data1, value: data2))
                default: continue
                }
            }
            return events
        }
    }
}

enum MidiError: VigilError {
    case clientFailed, portFailed

    var messageKey: String.LocalizationValue {
        switch self {
        case .clientFailed: "Não foi possível abrir o MIDI."
        case .portFailed: "Não foi possível abrir a entrada MIDI."
        }
    }
}
