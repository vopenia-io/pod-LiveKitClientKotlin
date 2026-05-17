import AVFoundation
import CoreImage
import Foundation
import LiveKitClient
import UIKit
import Vision

/// Custom `VideoProcessor` that replaces the background of each captured frame
/// with a still image, using Apple Vision (`VNGeneratePersonSegmentationRequest`)
/// for person segmentation and CoreImage to composite the result.
///
/// Mirrors `BackgroundBlurVideoProcessor` (LiveKit native) but for arbitrary
/// images instead of a blur. iOS 15+.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
@objc
public class BackgroundImageVideoProcessor: NSObject, LiveKitClient.VideoProcessor {

    private let backgroundCIImage: CIImage?
    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private let ciContext: CIContext

    @objc
    public init(image: UIImage?) {
        self.backgroundCIImage = image.flatMap { CIImage(image: $0) }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        self.segmentationRequest = request
        self.ciContext = CIContext(options: nil)
        super.init()
    }

    public func process(frame: VideoFrame) -> VideoFrame? {
        guard let bg = backgroundCIImage else { return frame }

        guard let pixelBuffer = (frame.buffer as? CVPixelVideoBuffer)?.pixelBuffer
            ?? extractPixelBuffer(from: frame) else {
            return frame
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            return frame
        }
        guard let mask = segmentationRequest.results?.first?.pixelBuffer else {
            return frame
        }

        let frameCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let maskCIImage = CIImage(cvPixelBuffer: mask)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])

        let scaleX = frameCIImage.extent.width / maskCIImage.extent.width
        let scaleY = frameCIImage.extent.height / maskCIImage.extent.height
        let scaledMask = maskCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let scaledBg = bg
            .transformed(by: CGAffineTransform(
                scaleX: frameCIImage.extent.width / bg.extent.width,
                y: frameCIImage.extent.height / bg.extent.height
            ))

        guard let blended = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: frameCIImage,
            kCIInputBackgroundImageKey: scaledBg,
            kCIInputMaskImageKey: scaledMask
        ])?.outputImage else {
            return frame
        }

        // Render back into a fresh CVPixelBuffer at the same dimensions.
        var outputBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(frameCIImage.extent.width),
            Int(frameCIImage.extent.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputBuffer
        )
        guard let outBuf = outputBuffer else { return frame }
        ciContext.render(blended, to: outBuf)

        let newBuffer = CVPixelVideoBuffer(pixelBuffer: outBuf)
        return VideoFrame(
            dimensions: frame.dimensions,
            rotation: frame.rotation,
            timeStampNs: frame.timeStampNs,
            buffer: newBuffer
        )
    }

    private func extractPixelBuffer(from frame: VideoFrame) -> CVPixelBuffer? {
        // Fallback for non-CVPixelVideoBuffer frames: we currently bail.
        // LiveKit's iOS camera pipeline produces CVPixelVideoBuffer by default,
        // so this path should not be exercised for the local camera track.
        return nil
    }
}
