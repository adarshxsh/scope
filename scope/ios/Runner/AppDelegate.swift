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
      let channel = FlutterMethodChannel(
        name: "com.scope.attentions/storage",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "excludeFromBackup" {
          self?.excludeApplicationSupportFromBackup()
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func excludeApplicationSupportFromBackup() {
    guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }
    do {
      try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      var mutableURL = appSupportURL
      try mutableURL.setResourceValues(resourceValues)

      if let enumerator = FileManager.default.enumerator(at: appSupportURL, includingPropertiesForKeys: nil) {
        for case let fileURL as URL in enumerator {
          var itemURL = fileURL
          try? itemURL.setResourceValues(resourceValues)
        }
      }
    } catch {
      print("Failed to set NSURLIsExcludedFromBackupKey: \(error)")
    }
  }
}
