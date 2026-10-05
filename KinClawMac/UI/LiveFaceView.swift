import SwiftUI

/// Her face as kin-face streams it (`LiveFace`), the whole picture in the panel.
///
/// Fitted, not filled: the panel can be any shape — Jacky's is wide — and a
/// portrait frame filling a wide panel was blown up until only a band of her
/// face showed (「页面显示太大了」). The space beside her is dark, as a video
/// call's is; her own room is in the picture.
struct LiveFaceView: View {
    @ObservedObject var face: LiveFace

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let frame = face.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Text(face.problem ?? "在接通她（盒子上的实时口型）…")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
        }
    }
}
