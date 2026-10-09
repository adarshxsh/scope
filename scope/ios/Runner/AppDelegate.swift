import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.scope.notifications", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "setNonBackupFlag" {
          if let args = call.arguments as? [String: Any],
             let path = args["path"] as? String {
            var url = URL(fileURLWithPath: path)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            do {
              try url.setResourceValues(resourceValues)
              result(true)
            } catch {
              result(FlutterError(code: "SET_FLAG_FAILED", message: error.localizedDescription, details: nil))
            }
          } else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path required", details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
