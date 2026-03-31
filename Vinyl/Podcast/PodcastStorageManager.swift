import Foundation

class PodcastStorageManager: ObservableObject {
    @Published var subscriptions: [SubscribedPodcast] = []

    private let subscriptionsKey = "vinyl_podcast_subscriptions"
    private let playbackKey = "vinyl_podcast_playback"

    init() {
        loadSubscriptions()
    }

    // MARK: - Subscriptions

    func subscribe(podcast: PodcastSearchResult) {
        let sub = SubscribedPodcast(
            feedURL: podcast.feedURL,
            name: podcast.name,
            artist: podcast.artist,
            artworkURL: podcast.artworkURL,
            subscriptionDate: Date()
        )
        guard !subscriptions.contains(where: { $0.feedURL == sub.feedURL }) else { return }
        subscriptions.append(sub)
        saveSubscriptions()
    }

    func subscribeFeed(_ feed: PodcastFeed, artist: String) {
        let sub = SubscribedPodcast(
            feedURL: feed.feedURL,
            name: feed.name,
            artist: artist,
            artworkURL: feed.artworkURL,
            subscriptionDate: Date()
        )
        guard !subscriptions.contains(where: { $0.feedURL == sub.feedURL }) else { return }
        subscriptions.append(sub)
        saveSubscriptions()
    }

    func unsubscribe(feedURL: String) {
        subscriptions.removeAll { $0.feedURL == feedURL }
        saveSubscriptions()
    }

    func isSubscribed(feedURL: String) -> Bool {
        subscriptions.contains { $0.feedURL == feedURL }
    }

    private func loadSubscriptions() {
        guard let data = UserDefaults.standard.data(forKey: subscriptionsKey),
              let decoded = try? JSONDecoder().decode([SubscribedPodcast].self, from: data) else { return }
        subscriptions = decoded
    }

    private func saveSubscriptions() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        UserDefaults.standard.set(data, forKey: subscriptionsKey)
    }

    // MARK: - Playback Position

    func savePlaybackPosition(episodeId: String, time: TimeInterval) {
        var positions = loadPlaybackPositions()
        positions[episodeId] = time
        guard let data = try? JSONEncoder().encode(positions) else { return }
        UserDefaults.standard.set(data, forKey: playbackKey)
    }

    func getPlaybackPosition(episodeId: String) -> TimeInterval {
        let positions = loadPlaybackPositions()
        return positions[episodeId] ?? 0
    }

    private func loadPlaybackPositions() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: playbackKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else { return [:] }
        return decoded
    }
}
