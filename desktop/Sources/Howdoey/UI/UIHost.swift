// Single entry point the coordinator uses. Owns all UI windows and installs the AppModel presentation hooks.
// Usage (from the app lifecycle): let host = UIHost(model: model); host.install(); host.togglePanel()
import AppKit
import Combine

@MainActor final class UIHost {
    let model: AppModel
    private let panel: ChatPanelController
    private let selection = SelectionOverlayController()
    private let demo: DemoOverlayController
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        panel = ChatPanelController(model: model)
        demo = DemoOverlayController(model: model)
    }

    func showPanel() { panel.show() }
    func hidePanel() { panel.hide() }
    func togglePanel() { panel.isVisible ? panel.hide() : panel.show() }

    func install() {
        model.showPanelHandler = { [weak self] in self?.panel.show() }
        model.closePanelHandler = { [weak self] in self?.panel.hide() }
        model.demonstrationHandler = { [weak self] target in
            guard let self else { return }
            if target == nil { demo.hideOverlay() } else { demo.showOverlay() }
        }
        model.selectionHandler = { [weak self] kind in self?.beginSelection(kind) }

        selection.onResult = { [weak self] region, app in self?.model.acceptSelection(app: app, region: region) }
        selection.onCancel = { [weak self] in self?.model.selectionCancelled() }
        selection.onFailure = { [weak self] message in
            self?.model.errorMessage = message
            self?.model.selectionCancelled()
        }

        // Step controls follow the backend's phase only. Nothing here advances a step.
        model.$phase.receive(on: DispatchQueue.main).sink { [weak self] phase in
            guard let self else { return }
            if phase == .demonstrating || phase == .verifying { demo.showControls(near: model.demonstration?.rect) } else { demo.hideControls() }
            // Stop (or any backend reset) while selecting must not leave a full-screen overlay behind.
            if phase != .selecting && selection.isActive { selection.end() }
        }.store(in: &cancellables)
    }

    private func beginSelection(_ kind: SelectionKind) {
        guard kind != .element else {
            model.errorMessage = "Selecting a single control isn't available yet. Select an area or a window instead."
            model.selectionCancelled()
            return
        }
        panel.hide() // keep Howdoey's own window out of the capture
        selection.begin(kind: kind)
    }
}
