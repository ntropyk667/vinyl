import Foundation

class RSSFeedParser: NSObject, ObservableObject, XMLParserDelegate {
    @Published var feed: PodcastFeed?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var feedURL: String = ""
    private var currentElement = ""
    private var currentText = ""

    // Channel-level
    private var channelTitle = ""
    private var channelDescription = ""
    private var channelArtwork = ""

    // Item-level
    private var inItem = false
    private var itemTitle = ""
    private var itemDescription = ""
    private var itemAudioURL = ""
    private var itemDuration = ""
    private var itemPubDate = ""
    private var itemGuid = ""
    private var itemEpisodeNumber = ""

    private var episodes: [PodcastEpisode] = []
    private var fetchTask: URLSessionDataTask?

    func fetchFeed(url: String) {
        guard let feedURL = URL(string: url) else {
            errorMessage = "Invalid feed URL"
            return
        }

        fetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        self.feedURL = url
        episodes = []
        channelTitle = ""
        channelDescription = ""
        channelArtwork = ""

        fetchTask = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }

            if let error = error {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "Feed fetch failed: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "No data received"
                }
                return
            }

            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
        }
        fetchTask?.resume()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            inItem = true
            itemTitle = ""
            itemDescription = ""
            itemAudioURL = ""
            itemDuration = ""
            itemPubDate = ""
            itemGuid = ""
            itemEpisodeNumber = ""
        }

        // Enclosure tag contains the MP3 URL
        if elementName == "enclosure", let url = attributeDict["url"] {
            let type = attributeDict["type"] ?? ""
            if type.contains("audio") || url.hasSuffix(".mp3") || url.hasSuffix(".m4a") || url.hasSuffix(".wav") {
                itemAudioURL = url
            }
        }

        // iTunes artwork (channel level)
        if elementName == "itunes:image", let href = attributeDict["href"], !inItem {
            channelArtwork = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch elementName {
            case "title": itemTitle = trimmed
            case "description": itemDescription = trimmed
            case "itunes:duration": itemDuration = trimmed
            case "pubDate": itemPubDate = trimmed
            case "guid": itemGuid = trimmed
            case "itunes:episode": itemEpisodeNumber = trimmed
            case "item":
                // Finished parsing an item — create episode
                if let audioURL = URL(string: itemAudioURL), !itemAudioURL.isEmpty {
                    let episode = PodcastEpisode(
                        id: itemGuid.isEmpty ? itemTitle : itemGuid,
                        title: itemTitle,
                        description: stripHTML(itemDescription),
                        audioURL: audioURL,
                        duration: parseDuration(itemDuration),
                        pubDate: parseDate(itemPubDate),
                        episodeNumber: Int(itemEpisodeNumber)
                    )
                    episodes.append(episode)
                }
                inItem = false
            default: break
            }
        } else {
            switch elementName {
            case "title":
                if channelTitle.isEmpty { channelTitle = trimmed }
            case "description":
                if channelDescription.isEmpty { channelDescription = stripHTML(trimmed) }
            default: break
            }
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        DispatchQueue.main.async { [self] in
            isLoading = false
            feed = PodcastFeed(
                name: channelTitle,
                feedURL: feedURL,
                description: channelDescription,
                artworkURL: channelArtwork,
                episodes: episodes
            )
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        DispatchQueue.main.async { [self] in
            isLoading = false
            errorMessage = "Failed to parse feed"
            print("RSS parse error: \(parseError)")
        }
    }

    // MARK: - Helpers

    private func parseDuration(_ str: String) -> TimeInterval {
        // Handle HH:MM:SS, MM:SS, or raw seconds
        let parts = str.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }

    private func parseDate(_ str: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // RSS uses RFC 2822 date format
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: str) { return date }
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: str) { return date }
        return Date.distantPast
    }

    private func stripHTML(_ str: String) -> String {
        // Pure regex stripping — NSAttributedString HTML parsing crashes on background threads
        var result = str
        // Remove HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#x2019;", "\u{2019}"), ("&#x2018;", "\u{2018}"),
            ("&#x201C;", "\u{201C}"), ("&#x201D;", "\u{201D}")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Collapse whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
