import SwiftUI

// MARK: - TVAuthImage
//
// AsyncImage can't attach an Authorization header, which the per-user artwork
// endpoint requires. This loads the image via URLSession with an optional Bearer
// token and falls back to a placeholder.

struct TVAuthImage<Placeholder: View>: View {
    let url: URL?
    let token: String?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let (data, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let ui = UIImage(data: data) {
            image = ui
        }
    }
}
