import Flutter
import UIKit
import AVFoundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.damumu.damu/permissions",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "request", let permission = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      if permission == "camera" {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: result("granted")
        case .notDetermined:
          AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { result(granted ? "granted" : "denied") }
          }
        default: result("settings")
        }
      } else if permission == "notifications" {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
          if settings.authorizationStatus == .denied {
            DispatchQueue.main.async { result("settings") }
            return
          }
          center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async { result(error != nil ? "failed" : (granted ? "granted" : "denied")) }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
