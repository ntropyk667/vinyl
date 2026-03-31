import SwiftUI

struct PodcastDetailView: View {
    @ObservedObject var engine: VinylEngine
    @ObservedObject var storage: PodcastStorageManager
    @StateObject private var parser = RSSFeedParser()
    @Environment(\.dismiss) var dismiss

    let feedURL: String
    let podcastName: String
    let artist: String
    let artworkURL: String

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0e0e0e").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Podcast header
                        podcastHeader

                        // Loading / Error
                        if parser.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color(hex: "c8b89a"))
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        }

                        if let error = parser.errorMessage {
                            Text(error)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                                .padding(.horizontal, 14)
                        }

                        // Episodes
                        if let feed = parser.feed {
                            Text("EPISODES")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(hex: "5a5856")).kerning(1.2)
                                .padding(.horizontal, 14)

                            ForEach(Array(feed.episodes.enumerated()), id: \.element.id) { index, episode in
                                EpisodeRow(episode: episode, storage: storage) {
                                    // Set episode list context for skip forward/back
                                    engine.setPodcastEpisodeList(feed.episodes, currentIndex: index)
                                    let resumeTime = storage.getPlaybackPosition(episodeId: episode.id)
                                    engine.playPodcastEpisode(episode, resumeFrom: resumeTime)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(podcastName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "c8b89a"))
                }
            }
            .onAppear {
                parser.fetchFeed(url: feedURL)
            }
        }
    }

    private var podcastHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                AsyncImage(url: URL(string: artworkURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle().fill(Color(hex: "1e1e1e"))
                            .overlay(Image(systemName: "mic.fill").foregroundColor(Color(hex: "5a5856")).font(.system(size: 20)))
                    default:
                        Rectangle().fill(Color(hex: "1e1e1e"))
                    }
                }
                .frame(width: 80, height: 80)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(podcastName)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "e8e6e0"))
                        .lineLimit(2)
                    Text(artist)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "5a5856"))
                    if let feed = parser.feed {
                        Text("\(feed.episodes.count) episodes")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "5a5856"))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)

            // Subscribe / Unsubscribe button
            Button(action: {
                if storage.isSubscribed(feedURL: feedURL) {
                    storage.unsubscribe(feedURL: feedURL)
                } else if let feed = parser.feed {
                    storage.subscribeFeed(feed, artist: artist)
                }
            }) {
                Text(storage.isSubscribed(feedURL: feedURL) ? "unsubscribe" : "subscribe")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(storage.isSubscribed(feedURL: feedURL) ? Color(hex: "5a5856") : Color(hex: "c8b89a"))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                        storage.isSubscribed(feedURL: feedURL) ? Color.white.opacity(0.08) : Color(hex: "c8b89a").opacity(0.4),
                        lineWidth: 0.5))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 14)

            // Description
            if let feed = parser.feed, !feed.description.isEmpty {
                Text(feed.description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "9a9690"))
                    .lineLimit(4)
                    .padding(.horizontal, 14)
            }

            Divider().opacity(0.15).padding(.horizontal, 14)
        }
    }
}

struct EpisodeRow: View {
    let episode: PodcastEpisode
    let storage: PodcastStorageManager
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Image(systemName: hasResume ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "c8b89a"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "e8e6e0"))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if episode.duration > 0 {
                            Text(episode.formattedDuration)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(hex: "5a5856"))
                        }
                        Text(episode.formattedDate)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: "5a5856"))
                        if hasResume {
                            Text("resume")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(hex: "5a9a78"))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
            .padding(.horizontal, 14)
        }
    }

    private var hasResume: Bool {
        storage.getPlaybackPosition(episodeId: episode.id) > 10
    }
}
