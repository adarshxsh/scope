import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    excludeApplicationSupportDirectoryFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func excludeApplicationSupportDirectoryFromBackup() {
    let fileManager = FileManager.default
    if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      do {
        if !fileManager.fileExists(atPath: appSupportURL.path) {
          try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        var mutableURL = appSupportURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)

        let nsurl = appSupportURL as NSURL
        try nsurl.setResourceValue(true, forKey: .isExcludedFromBackupKey)
      } catch {
        print("Failed to set NSURLIsExcludedFromBackupKey on Application Support directory: \(error)")
      }
    }
  }
}
