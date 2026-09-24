import SwiftUI

/// A separate window also covers presented sheets and the system camera picker.
struct PrivacyShield: UIViewRepresentable {
    var visible: Bool

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.updateVisibility = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window?.windowScene)
        }
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.visible = visible
        context.coordinator.attach(to: view.window?.windowScene)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.shield?.isHidden = true
        coordinator.shield = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class AnchorView: UIView {
        var updateVisibility: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); updateVisibility?(window) }
    }

    @MainActor final class Coordinator {
        var shield: UIWindow?
        var visible = false
        func attach(to scene: UIWindowScene?) {
            guard let scene else { return }
            if shield == nil {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                let controller = UIViewController()
                controller.view.backgroundColor = UIColor(Theme.background)
                let label = UILabel()
                label.text = "HEIMDALL  ·  PROTECTED"
                label.textColor = UIColor(Theme.accent)
                label.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
                label.translatesAutoresizingMaskIntoConstraints = false
                controller.view.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
                ])
                window.rootViewController = controller
                shield = window
            }
            shield?.isHidden = !visible
        }
    }
}
