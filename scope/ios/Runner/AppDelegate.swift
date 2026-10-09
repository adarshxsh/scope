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
      let channel = FlutterMethodChannel(
        name: "scope/backup_protection",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "excludeFromBackup" {
          guard let args = call.arguments as? [String: Any],
                let path = (args["path"] as? String) ?? (args["filePath"] as? String) else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path parameter is required", details: nil))
            return
          }
          var fileUrl = URL(fileURLWithPath: path)
          do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try fileUrl.setResourceValues(resourceValues)
            result(true)
          } catch {
            result(FlutterError(code: "EXCLUSION_FAILED", message: error.localizedDescription, details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
