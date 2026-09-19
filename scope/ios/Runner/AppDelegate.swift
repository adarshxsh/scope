import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let keystoreChannel = FlutterMethodChannel(name: "com.scope.keystore", binaryMessenger: controller.binaryMessenger)
    let securityChannel = FlutterMethodChannel(name: "com.scope.attentions/security", binaryMessenger: controller.binaryMessenger)

    let handleCall: (FlutterMethodCall, @escaping FlutterResult) -> Void = { call, result in
      if call.method == "getDatabaseKey" {
        if let key = self.getOrCreateKeychainKey() {
          result(key)
        } else {
          result(FlutterError(code: "KEY_ERROR", message: "Failed to generate or retrieve keychain key", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    keystoreChannel.setMethodCallHandler(handleCall)
    securityChannel.setMethodCallHandler(handleCall)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func getOrCreateKeychainKey() -> String? {
    let service = "com.scope.attentions"
    let account = "db_encryption_key"

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) {
      return key
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard randomStatus == errSecSuccess else { return nil }
    let hexKey = bytes.map { String(format: "%02x", $0) }.joined()

    if let keyData = hexKey.data(using: .utf8) {
      let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: keyData,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      ]
      SecItemAdd(addQuery as CFDictionary, nil)
    }

    return hexKey
  }
}
