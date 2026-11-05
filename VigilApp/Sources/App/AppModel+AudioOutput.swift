import Foundation

extension AppModel {

    /// Reads the saved buffer size and output, then routes the engine to them once.
    func restoreOutput() {
        let saved = defaults.integer(forKey: bufferKey)
        if saved > 0 { bufferFrames = saved }
        outputDeviceUID = defaults.string(forKey: outputKey)
        applyOutput()
    }

    /// Applies the current choices. A missing device falls back to the system output with a
    /// toast, so a show never starts silent because an interface was left at home. Until the
    /// engine runs the choices are only remembered; `start()` applies them.
    func applyOutput() {
        guard graph.engine.isRunning else { return }
        do {
            activeBuffer = try graph.applyOutput(uid: outputDeviceUID, bufferFrames: bufferFrames)
        } catch let error as OutputError {
            toasts.error(t(error.messageKey))
            if case .deviceMissing = error { outputDeviceUID = nil }
        } catch {
            toasts.error(t("Não foi possível iniciar o áudio."))
        }
    }
}
