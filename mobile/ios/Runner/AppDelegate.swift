import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let keystoreHandler = KeystoreHandler()
  private let passkeyHandler = PasskeyHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: KeystoreHandler.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.keystoreHandler.handle(call, result: result)
      }

      let passkeyChannel = FlutterMethodChannel(
        name: PasskeyHandler.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      passkeyChannel.setMethodCallHandler { [weak self] call, result in
        self?.passkeyHandler.handle(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
