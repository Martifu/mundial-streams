import Foundation

enum EmbedCodeBuilder {
    static func iframe(for url: URL) -> String {
        #"""
        <iframe src="\#(url.absoluteString)" width="100%" height="100%" frameborder="0" scrolling="no" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        """#
    }
}
