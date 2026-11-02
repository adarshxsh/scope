import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let backupChannel = FlutterMethodChannel(
        name: "com.scope.backup",
        binaryMessenger: controller.binaryMessenger
      )
      backupChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "excludeFromBackup" {
          if let args = call.arguments as? [String: Any],
             let fileName = args["fileName"] as? String {
            let filePath = args["filePath"] as? String
            let success = self.excludeFileFromBackup(fileName: fileName, filePath: filePath)
            result(success)
          } else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "File name missing", details: nil))
          }
        } else if call.method == "excludeDefaultFiles" {
          self.excludeDefaultFilesFromBackup()
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Apply NSURLIsExcludedFromBackupKey attribute on default sensitive files on startup
    excludeDefaultFilesFromBackup()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc public func excludeDefaultFilesFromBackup() {
    let filesToExclude = ["attention_os.db", "rlhf_rules.json"]
    for fileName in filesToExclude {
      _ = excludeFileFromBackup(fileName: fileName, filePath: nil)
    }
  }

  @objc public func excludeFileFromBackup(fileName: String, filePath: String?) -> Bool {
    let targetUrl: URL
    if let filePath = filePath, !filePath.isEmpty {
      targetUrl = URL(fileURLWithPath: filePath)
    } else {
      guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return false
      }
      targetUrl = documentsUrl.appendingPathComponent(fileName)
    }
    return setBackupExclusionAttribute(url: targetUrl)
  }

  @discardableResult
  private func setBackupExclusionAttribute(url: URL) -> Bool {
    var fileUrl = url
    if FileManager.default.fileExists(atPath: fileUrl.path) {
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      do {
        try fileUrl.setResourceValues(resourceValues)
        return true
      } catch {
        print("Failed to set NSURLIsExcludedFromBackupKey on \(fileUrl.path): \(error)")
        return false
      }
    }
    return false
  }
}
