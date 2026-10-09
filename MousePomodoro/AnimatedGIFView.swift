import SwiftUI
import AppKit
import ImageIO

/// Plays a bundled animated GIF (milestone celebrations) — AppKit's `NSImageView`
/// doesn't auto-animate GIF frame data, so this steps frames manually using each
/// frame's own delay from the GIF's metadata.
struct AnimatedGIFView: NSViewRepresentable {
    let resourceName: String
    var size: CGFloat = 128

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        context.coordinator.start(in: view, resourceName: resourceName)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var timer: Timer?
        private var frames: [(image: NSImage, delay: TimeInterval)] = []
        private var index = 0

        func start(in view: NSImageView, resourceName: String) {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "gif"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }

            let count = CGImageSourceGetCount(source)
            for i in 0..<count {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                var delay = 0.1
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                   let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                    if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                        delay = unclamped
                    } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double {
                        delay = clamped
                    }
                }
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                frames.append((NSImage(cgImage: cgImage, size: size), max(delay, 0.02)))
            }
            guard !frames.isEmpty else { return }
            view.image = frames[0].image
            scheduleNext(in: view)
        }

        private func scheduleNext(in view: NSImageView) {
            guard !frames.isEmpty else { return }
            let delay = frames[index].delay
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.index = (self.index + 1) % self.frames.count
                view.image = self.frames[self.index].image
                self.scheduleNext(in: view)
            }
        }

        deinit {
            timer?.invalidate()
        }
    }
}
