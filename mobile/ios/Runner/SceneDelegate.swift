import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    private let blurTag = 9999

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        guard let window = self.window else { return }
        let blur = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.frame = window.bounds
        view.tag = blurTag
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        self.window?.viewWithTag(blurTag)?.removeFromSuperview()
    }
}
