import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let backupChannel = FlutterMethodChannel(name: "com.scope.attentions/backup_exclusion",
                                             binaryMessenger: controller.binaryMessenger)
    backupChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "excludeFromBackup" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Path parameter is required", details: nil))
          return
        }
        do {
          var url = URL(fileURLWithPath: path)
          var resourceValues = URLResourceValues()
          resourceValues.isExcludedFromBackup = true
          try url.setResourceValues(resourceValues)
          result(true)
        } catch {
          result(FlutterError(code: "EXCLUSION_ERROR", message: error.localizedDescription, details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
