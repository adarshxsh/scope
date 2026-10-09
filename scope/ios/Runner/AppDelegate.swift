import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeApplicationSupportFromBackup()

    if let controller = window?.rootViewController as? FlutterViewController {
      let backupChannel = FlutterMethodChannel(
        name: "com.scope.backup_exclusion",
        binaryMessenger: controller.binaryMessenger
      )
      backupChannel.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "excludeFromBackup" {
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path parameter is required", details: nil))
            return
          }
          let fileURL = URL(fileURLWithPath: path)
          var mutableURL = fileURL
          do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try mutableURL.setResourceValues(resourceValues)
            result(true)
          } catch {
            result(FlutterError(code: "EXCLUSION_FAILED", message: error.localizedDescription, details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      })
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func excludeApplicationSupportFromBackup() {
    guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    do {
      if !FileManager.default.fileExists(atPath: appSupportURL.path) {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
      }
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      var mutableURL = appSupportURL
      try mutableURL.setResourceValues(resourceValues)
    } catch {
      print("Failed to exclude application support directory from backup: \(error)")
    }
  }
}
