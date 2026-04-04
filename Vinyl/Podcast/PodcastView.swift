import SwiftUI

struct PodcastView: View {
    @ObservedObject var engine: VinylEngine
    @ObservedObject var storage: PodcastStorageManager
    @StateObject private var searcher = PodcastSearcher()
    @State private var searchText = ""
    @State private var selectedPodcast: PodcastSearchResult?
    @State private var selectedSubscription: SubscribedPodcast?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("podcasts")

            // Search bar with clear button
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "5a5856"))
                    TextField("search podcasts", text: $searchText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "e8e6e0"))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { searcher.search(searchText) }
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searcher.results = []
                            searcher.errorMessage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "5a5856"))
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(hex: "161616"))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .cornerRadius(6)

                if searcher.isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color(hex: "c8b89a"))
                }
            }

            // Loading indicator for podcast episode
            if engine.isPodcastLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(Color(hex: "5a9a78"))
                    Text("loading episode...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "5a9a78"))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }

            // Error message
            if let error = engine.podcastLoadError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
            }

            // Subscribed podcasts — icon grid
            if !storage.subscriptions.isEmpty && searchText.isEmpty {
                Text("subscribed")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white).kerning(1.2)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 8)], spacing: 8) {
                    ForEach(storage.subscriptions) { sub in
                        Button(action: {
                            selectedSubscription = sub
                        }) {
                            VStack(spacing: 3) {
                                AsyncImage(url: URL(string: sub.artworkURL)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    case .failure:
                                        Rectangle().fill(Color(hex: "1e1e1e"))
                                            .overlay(Image(systemName: "mic.fill").foregroundColor(Color(hex: "5a5856")).font(.system(size: 14)))
                                    default:
                                        Rectangle().fill(Color(hex: "1e1e1e"))
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .cornerRadius(6)

                                Text(sub.name)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(Color(hex: "9a9690"))
                                    .lineLimit(1)
                                    .frame(width: 52)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Search results
            if !searcher.results.isEmpty {
                Text("results")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856")).kerning(1.2)
                    .padding(.top, 4)

                ForEach(searcher.results) { result in
                    Button(action: {
                        selectedPodcast = result
                    }) {
                        PodcastRow(name: result.name, artist: result.artist, artworkURL: result.artworkURL)
                    }
                }
            }

            if let error = searcher.errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856"))
                    .padding(.horizontal, 10)
            }
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailView(
                engine: engine,
                storage: storage,
                feedURL: podcast.feedURL,
                podcastName: podcast.name,
                artist: podcast.artist,
                artworkURL: podcast.artworkURL,
                onDismissAction: { clearSearchResults() }
            )
        }
        .sheet(item: $selectedSubscription) { sub in
            PodcastDetailView(
                engine: engine,
                storage: storage,
                feedURL: sub.feedURL,
                podcastName: sub.name,
                artist: sub.artist,
                artworkURL: sub.artworkURL,
                onDismissAction: { clearSearchResults() }
            )
        }
    }

    private func clearSearchResults() {
        searchText = ""
        searcher.results = []
        searcher.errorMessage = nil
    }
}

struct PodcastRow: View {
    let name: String
    let artist: String
    let artworkURL: String

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: artworkURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Color(hex: "1e1e1e"))
                        .overlay(Image(systemName: "mic.fill").foregroundColor(Color(hex: "5a5856")).font(.system(size: 12)))
                default:
                    Rectangle().fill(Color(hex: "1e1e1e"))
                }
            }
            .frame(width: 36, height: 36)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "e8e6e0"))
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856"))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "5a5856"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(hex: "161616"))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .cornerRadius(6)
    }
}

// Make PodcastSearchResult work with .sheet(item:)
extension PodcastSearchResult: Equatable {
    static func == (lhs: PodcastSearchResult, rhs: PodcastSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

extension SubscribedPodcast: Equatable {
    static func == (lhs: SubscribedPodcast, rhs: SubscribedPodcast) -> Bool {
        lhs.feedURL == rhs.feedURL
    }
}
