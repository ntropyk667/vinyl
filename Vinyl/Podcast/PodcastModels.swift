import Foundation

struct PodcastSearchResult: Identifiable, Codable {
    let id: String
    let name: String
    let artist: String
    let feedURL: String
    let artworkURL: String
    let description: String
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "collectionId"
        case name = "collectionName"
        case artist = "artistName"
        case feedURL = "feedUrl"
        case artworkURL = "artworkUrl600"
        case episodeCount = "trackCount"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // collectionId can be Int or String
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        name = try c.decode(String.self, forKey: .name)
        artist = (try? c.decode(String.self, forKey: .artist)) ?? "Unknown"
        feedURL = (try? c.decode(String.self, forKey: .feedURL)) ?? ""
        artworkURL = (try? c.decode(String.self, forKey: .artworkURL)) ?? ""
        description = name  // iTunes search doesn't return a separate description
        episodeCount = try? c.decode(Int.self, forKey: .episodeCount)
    }

    init(id: String, name: String, artist: String, feedURL: String, artworkURL: String, description: String, episodeCount: Int?) {
        self.id = id; self.name = name; self.artist = artist; self.feedURL = feedURL
        self.artworkURL = artworkURL; self.description = description; self.episodeCount = episodeCount
    }
}

struct PodcastSearchResponse: Codable {
    let resultCount: Int
    let results: [PodcastSearchResult]
}

struct PodcastEpisode: Identifiable {
    let id: String          // guid from RSS
    let title: String
    let description: String?
    let audioURL: URL
    let duration: TimeInterval
    let pubDate: Date
    let episodeNumber: Int?

    var formattedDuration: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: pubDate)
    }
}

struct PodcastFeed {
    let name: String
    let feedURL: String
    let description: String
    let artworkURL: String
    let episodes: [PodcastEpisode]
}

struct SubscribedPodcast: Codable, Identifiable {
    var id: String { feedURL }
    let feedURL: String
    let name: String
    let artist: String
    let artworkURL: String
    let subscriptionDate: Date
}
