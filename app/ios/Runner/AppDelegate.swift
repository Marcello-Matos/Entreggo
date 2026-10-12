import Flutter
import UIKit
import Vision

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LabelTextRecognizer") {
      LabelTextRecognizer.register(with: registrar)
    }
  }
}

/// Reconhecimento de texto de etiquetas com o framework Vision (no aparelho, sem internet).
final class LabelTextRecognizer: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "entreggo/text_recognition", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LabelTextRecognizer(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize",
      let path = (call.arguments as? [String: Any])?["path"] as? String,
      let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage
    else {
      result(FlutterError(code: "invalid_image", message: "Imagem inválida", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      let lines: [String]
      if error != nil {
        lines = []
      } else {
        // Ordena de cima para baixo e da esquerda para a direita (origem do Vision é embaixo).
        lines = (request.results as? [VNRecognizedTextObservation] ?? [])
          .sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
              ? $0.boundingBox.midY > $1.boundingBox.midY
              : $0.boundingBox.minX < $1.boundingBox.minX
          }
          .compactMap { $0.topCandidates(1).first?.string }
      }
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
        } else {
          result(lines)
        }
      }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["pt-BR", "en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(
      cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
