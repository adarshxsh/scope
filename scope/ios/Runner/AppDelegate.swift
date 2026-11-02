import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let backupChannel = FlutterMethodChannel(
      name: "scope/backup_protection",
      binaryMessenger: controller.binaryMessenger
    )

    backupChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "excludeFromBackup" {
        var path: String? = nil
        if let args = call.arguments as? [String: Any] {
          path = args["path"] as? String ?? args["filePath"] as? String
        } else if let strPath = call.arguments as? String {
          path = strPath
        }

        guard let filePath = path, !filePath.isEmpty else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Path argument missing or invalid", details: nil))
          return
        }

        var url = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: filePath) {
          do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
            result(true)
          } catch {
            result(FlutterError(code: "EXCLUSION_FAILED", message: error.localizedDescription, details: nil))
          }
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
