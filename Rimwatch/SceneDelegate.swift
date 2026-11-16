import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    // Losing focus or going to the background pauses like closing the phone. Coming back shows
    // the pause menu; nothing resumes on its own.
    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? GameViewController)?.appWillResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? GameViewController)?.appWillResignActive()
    }
}
