import SwiftUI

/// Output device and buffer size, with the latency the hardware is actually running.
struct AudioOutputRows: View {
    @Bindable var model: AppModel

    @Environment(\.theme) private var theme
    #if os(macOS)
    @State private var devices: [OutputDevice] = []
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS)
            pickerRow("Dispositivo") {
                Picker("Dispositivo", selection: $model.outputDeviceUID) {
                    Text("Sistema").tag(String?.none)
                    ForEach(devices) { Text(verbatim: $0.name).tag(String?.some($0.uid)) }
                }
            }
            #endif
            pickerRow("Buffer") {
                Picker("Buffer", selection: $model.bufferFrames) {
                    ForEach(bufferChoices, id: \.self) { Text("\($0) frames").tag($0) }
                }
            }
            if let active = model.activeBuffer {
                Text("Latência de saída: \(active.milliseconds.formatted(.number.precision(.fractionLength(1)))) ms a \(Int(active.sampleRate)) Hz")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkMuted)
            }
            #if os(iOS)
            Text("No iPad a saída é escolhida pelo sistema, no AirPlay da Central de Controle.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkMuted)
            #else
            Text("Trocar de dispositivo interrompe o que estiver tocando. Buffer menor responde mais rápido; se o som falhar, aumente.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        #if os(macOS)
        .task { devices = AudioOutput.devices() }
        #endif
    }

    private var bufferChoices: [Int] {
        #if os(macOS)
        model.graph.bufferChoices(forUID: model.outputDeviceUID)
        #else
        AudioOutput.bufferChoices
        #endif
    }

    private func pickerRow(_ label: LocalizedStringKey, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
            Spacer()
            picker()
                .labelsHidden()
                .fixedSize()
        }
    }
}
