import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let storageChannel = FlutterMethodChannel(name: "com.scope.attentions/storage",
                                              binaryMessenger: controller.binaryMessenger)
    storageChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "excludeFromBackup" {
        if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          var url = URL(fileURLWithPath: path)
          var resourceValues = URLResourceValues()
          resourceValues.isExcludedFromBackup = true
          do {
            try url.setResourceValues(resourceValues)
            result(true)
          } catch {
            result(FlutterError(code: "EXCLUDE_FAILED", message: error.localizedDescription, details: nil))
          }
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Path argument required", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
