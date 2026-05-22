import CoreGraphics
import SwiftUI
import Vision

/// Renders the pose skeleton with a halo + cyan joints. Matches the
/// reference demo's polished look.
struct SkeletonOverlay: View {
    let landmarks: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let imageSize: CGSize
    let mirror: Bool

    var body: some View {
        Canvas { ctx, size in
            // Map normalized coords (0..1) to the on-screen aspect-fill rect.
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let imageAspect = imageSize.width / imageSize.height
            let viewAspect = size.width / size.height
            var scale: CGFloat
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if viewAspect > imageAspect {
                scale = size.width / imageSize.width
                dy = (size.height - imageSize.height * scale) / 2
            } else {
                scale = size.height / imageSize.height
                dx = (size.width - imageSize.width * scale) / 2
            }

            func project(_ p: CGPoint) -> CGPoint {
                let x = p.x * imageSize.width * scale + dx
                let y = p.y * imageSize.height * scale + dy
                return CGPoint(x: x, y: y)
            }

            // Halo first, then crisp bones, then joints.
            let halo = Path { p in
                for (a, b) in skeletonBones {
                    guard let pa = landmarks[a], let pb = landmarks[b] else { continue }
                    p.move(to: project(pa))
                    p.addLine(to: project(pb))
                }
            }
            ctx.stroke(halo, with: .color(.white.opacity(0.20)), lineWidth: 8)

            let bones = Path { p in
                for (a, b) in skeletonBones {
                    guard let pa = landmarks[a], let pb = landmarks[b] else { continue }
                    p.move(to: project(pa))
                    p.addLine(to: project(pb))
                }
            }
            ctx.stroke(bones, with: .color(.white), lineWidth: 3)

            for (_, pt) in landmarks {
                let p = project(pt)
                let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.22, green: 0.88, blue: 1.0)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}
