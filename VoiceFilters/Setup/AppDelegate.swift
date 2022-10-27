import UIKit

@UIApplicationMain
class AppDelegate : UIResponder, UIApplicationDelegate {

    var window : UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions
        launchOptions: [UIApplication.LaunchOptionsKey : Any]?
    )-> Bool {
        if #available(iOS 13, *) {
            return true
        } else {
            self.window = UIWindow()
            let vc = VideoPlaybackBuilder.build()
            self.window!.rootViewController = vc
            self.window!.makeKeyAndVisible()
        }
        return true
    }
}
