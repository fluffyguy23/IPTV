import AppKit

enum Section: Int, CaseIterable {
    case home, liveTV, movies, series, favorites, recent, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .liveTV: return "Live TV"
        case .movies: return "Movies"
        case .series: return "Series"
        case .favorites: return "Favorites"
        case .recent: return "Recently Watched"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .liveTV: return "tv.fill"
        case .movies: return "film.fill"
        case .series: return "rectangle.stack.fill"
        case .favorites: return "star.fill"
        case .recent: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Lets child view controllers drive navigation, detail pushes, playback, and
/// section switching without knowing about the window.
protocol AppCoordinator: AnyObject {
    var session: Session { get }
    func selectSection(_ section: Section)
    func push(_ viewController: NSViewController)
    func pop()
    func openMovie(_ movie: VODStream)
    func openSeries(_ series: SeriesStream)
    /// Open a movie/episode in its own player window. `navigator` enables
    /// Prev/Next episode controls (series only).
    func playInWindow(_ item: PlaybackItem, navigator: EpisodeNavigator?)
    /// Play a stored reference (resume/favorites/recent) resolving its kind.
    func play(ref: MediaRef)
    func performSearch(_ query: String)
    func refreshCurrentProfile()
}
