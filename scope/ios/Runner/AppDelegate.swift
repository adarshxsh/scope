import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let backupChannel = FlutterMethodChannel(
      name: "scope/backup_protection",
      binaryMessenger: controller.binaryMessenger
    )

    backupChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "excludeFromBackup" {
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments must be a Map", details: nil))
          return
        }

        var pathsToExclude: [String] = []
        if let singlePath = args["path"] as? String {
          pathsToExclude.append(singlePath)
        }
        if let multiplePaths = args["paths"] as? [String] {
          pathsToExclude.append(contentsOf: multiplePaths)
        }

        for path in pathsToExclude {
          var url = URL(fileURLWithPath: path)
          if FileManager.default.fileExists(atPath: path) {
            do {
              var resourceValues = URLResourceValues()
              resourceValues.isExcludedFromBackup = true
              try url.setResourceValues(resourceValues)
            } catch {
              print("Error setting excludeFromBackup for \(path): \(error)")
            }
          }
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

