import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var secureField: UITextField?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.tidi.tidistockmobileapp/screen_protection",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableProtection":
        self?.enableScreenProtection()
        result(nil)
      case "disableProtection":
        self?.disableScreenProtection()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func enableScreenProtection() {
    guard secureField == nil else { return }
    DispatchQueue.main.async { [weak self] in
      guard let window = self?.window else { return }
      let field = UITextField()
      field.isSecureTextEntry = true
      field.isUserInteractionEnabled = false
      field.translatesAutoresizingMaskIntoConstraints = false
      window.addSubview(field)
      NSLayoutConstraint.activate([
        field.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        field.centerYAnchor.constraint(equalTo: window.centerYAnchor)
      ])
      window.layer.superlayer?.addSublayer(field.layer)
      field.layer.sublayers?.first?.addSublayer(window.layer)
      self?.secureField = field
    }
  }

  private func disableScreenProtection() {
    DispatchQueue.main.async { [weak self] in
      guard let field = self?.secureField, let window = self?.window else { return }
      // Restore window layer to its original position before removing the field
      if let originalSuperlayer = field.layer.superlayer {
        originalSuperlayer.addSublayer(window.layer)
      }
      field.layer.removeFromSuperlayer()
      field.removeFromSuperview()
      self?.secureField = nil
    }
  }
}
