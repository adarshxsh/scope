import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.scope.attentions/storage",
      binaryMessenger: controller.binaryMessenger
    )
    
    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "excludeFromBackup" {
        var filePath: String? = nil
        if let args = call.arguments as? [String: Any], let p = args["path"] as? String {
          filePath = p
        } else if let p = call.arguments as? String {
          filePath = p
        }
        
        guard let path = filePath, !path.isEmpty else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
          return
        }
        
        let success = self.setBackupExclusion(filePath: path)
        result(success)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // Perform startup backup exclusion pass on sensitive documents and application support files
    self.excludeSensitiveFilesFromBackup()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @discardableResult
  private func setBackupExclusion(filePath: String) -> Bool {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: filePath) {
      var url = URL(fileURLWithPath: filePath)
      do {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        return true
      } catch {
        print("Failed to set backup exclusion for \(filePath): \(error)")
        return false
      }
    }
    return false
  }

  private func excludeSensitiveFilesFromBackup() {
    let targetFiles = [
      "attention_os.db",
      "attention_os.db-wal",
      "attention_os.db-shm",
      "rlhf_rules.json"
    ]
    
    let fileManager = FileManager.default
    let searchDirs: [FileManager.SearchPathDirectory] = [.documentDirectory, .applicationSupportDirectory]
    
    for searchDir in searchDirs {
      if let dirUrl = fileManager.urls(for: searchDir, in: .userDomainMask).first {
        for fileName in targetFiles {
          let fileUrl = dirUrl.appendingPathComponent(fileName)
          if fileManager.fileExists(atPath: fileUrl.path) {
            setBackupExclusion(filePath: fileUrl.path)
          }
        }
      }
    }
  }
}
