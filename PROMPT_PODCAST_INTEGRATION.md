# Prompt: Podcast Integration for Vinyl

## Overview
Add podcast discovery and streaming to Vinyl. Users can search for podcasts via iTunes Search API, browse episodes, and play them through Vinyl's effect chain in real-time. All audio is streamed (no offline conversion required).

## User Flow
1. User opens Vinyl, navigates to "Podcasts" tab
2. Searches for a podcast by name (e.g., "Joe Rogan")
3. Selects a podcast from results → sees episode list
4. Picks an episode → streams the MP3 through Vinyl's effects
5. Listens with all vinyl warmth, crackle, wow/flutter applied in real-time
6. Can pause, seek, skip like normal playback
7. Option to subscribe to podcast (stores feed URL locally)

## Architecture

### Data Models
```swift
struct PodcastSearchResult {
    let id: String              // iTunes podcast ID
    let name: String
    let artist: String          // Podcast creator/publisher
    let feedURL: String         // RSS feed URL
    let artworkURL: String      // 600px+ image
    let description: String
    let episodeCount: Int?
}

struct PodcastFeed {
    let id: String
    let name: String
    let feedURL: String
    let description: String
    let artworkURL: String
    let episodes: [PodcastEpisode]
}

struct PodcastEpisode {
    let guid: String            // Unique ID (use for resume tracking)
    let title: String
    let description: String?
    let audioURL: URL           // Direct MP3 link from RSS
    let duration: TimeInterval
    let pubDate: Date
    let episodeNumber: Int?

    // Playback state
    var playbackTime: TimeInterval = 0  // Where user left off
}

struct SubscribedPodcast {
    let feedURL: String
    let name: String
    let artworkURL: String
    let subscriptionDate: Date
    var lastFetchedDate: Date
}
```

### iTunes Search API Integration
- Endpoint: `https://itunes.apple.com/search?term={query}&entity=podcast&limit=50`
- No authentication required
- Returns JSON with `feedUrl` key
- Rate limit: reasonable (not heavily documented, but no auth means no hard limit)

### RSS Feed Parsing
- Fetch RSS XML from `feedURL`
- Parse using `XMLParser` or third-party RSS library
- Extract: channel title, description, artwork, episodes
- Each `<item>` is an episode with `<enclosure>` tag containing MP3 URL

### VinylEngine Integration
- Existing playback chain works for HTTP streams (just like local files)
- No changes needed to effect processing
- New method: `func playPodcastStream(url: URL)` to load from HTTP instead of local file

### State Management
- Store subscribed podcasts in UserDefaults or CoreData
- Cache episode lists (don't re-fetch every time)
- Track playback position per episode (resume from where user left off)

## UI Design

### Tab Structure
Add "Podcasts" tab alongside existing library view in ContentView

### Screen 1: Podcast Search
```
┌─────────────────────────────┐
│ Podcasts                    │
├─────────────────────────────┤
│ [Search podcasts…______] ↩  │
├─────────────────────────────┤
│ Subscribed:                 │
│ • Joe Rogan Experience      │
│ • This American Life        │
│ • Reply All                 │
├─────────────────────────────┤
│ Search Results:             │
│ • Lore (Aaron Mahnke)       │
│ • Radiolab                  │
│ • Freakonomics Radio        │
└─────────────────────────────┘
```

### Screen 2: Podcast Details & Episodes
```
┌─────────────────────────────┐
│ ← Joe Rogan Experience      │
├─────────────────────────────┤
│ [Podcast Art]               │
│ Joe Rogan Experience        │
│ 2,847 episodes              │
│ [Subscribe] or [Unsubscribe]│
│                             │
│ Description (brief)         │
├─────────────────────────────┤
│ Latest Episodes:            │
│ ▶ #2154 Guest Name (3h 14m) │
│   Mar 28, 2026              │
│                             │
│ ▶ #2153 Guest Name (2h 48m) │
│   Mar 27, 2026              │
│                             │
│ ▶ #2152 Guest Name (3h 02m) │
│   Mar 26, 2026              │
└─────────────────────────────┘
```

### Screen 3: Now Playing (During Playback)
- Reuse existing TransportView
- Show podcast artwork, episode title, duration
- Standard play/pause, seek, progress bar
- All effect controls available (EQ, crackle, etc.)
- Preset selector still available

## Implementation Phases

### Phase 1: Search & Fetch
- Create `PodcastSearcher` class to hit iTunes API
- Parse search results into `PodcastSearchResult` objects
- Create `RSSFeedParser` to parse podcast RSS feeds
- Build search UI screen

### Phase 2: Episode Display & Subscription
- Display podcast details + episode list
- Implement subscribe/unsubscribe (save to UserDefaults)
- Show subscribed podcasts in tab
- Cache episode list locally with expiration

### Phase 3: Streaming Playback
- Modify VinylEngine to accept HTTP URLs (not just Bundle resources)
- Test streaming MP3 through effect chain
- Implement seek/pause/resume for streams
- Handle network errors gracefully

### Phase 4: Playback State
- Track user's playback position per episode (CoreData or UserDefaults)
- Resume from last position when user replays episode
- Show "Resume" button if episode has previous playback

### Phase 5: UI Polish
- Podcast artwork loading + caching
- Search result pagination
- Refresh subscribed feeds on app launch
- Handle offline episodes (show cached episodes)

## Technical Considerations

### HTTP Streaming in VinylEngine
Current setup loads from `Bundle` resources. To support HTTP:
1. Modify buffer loading to accept `URL` parameter
2. Use `AVAudioFile(forReading: url)` (works with HTTP URLs)
3. Handle timeout/connection errors gracefully
4. Consider buffer size for streaming (may need adjustment)

### Network Handling
- Network requests on background threads (DispatchQueue.global)
- Timeout handling (podcast feeds can be slow)
- Graceful degradation if feed is unreachable
- Cache episode lists to avoid repeated fetches

### Memory Management
- Don't load all episodes into memory at once (pagination/lazy load)
- Cache artwork images but implement eviction policy
- Stream audio directly (don't pre-buffer entire episode)

### Edge Cases
- Podcast with no artwork (use placeholder)
- Episode with no audio URL (skip)
- Very long episode titles (truncate/wrap)
- Feed fetch timeout (show cached, offer retry)
- User subscribes to 100+ podcasts (pagination/search)

## Testing Checklist
- [ ] Search returns correct podcast
- [ ] RSS feed parses without crashing
- [ ] Episode streams play through effects chain
- [ ] Pause/resume works during streaming
- [ ] Seek works (may have latency depending on host)
- [ ] Subscribe/unsubscribe persists
- [ ] Playback position saved and restored
- [ ] Network errors don't crash app
- [ ] Artwork loads and caches
- [ ] Effect settings work on podcast audio (same as music)

## Open Questions
- Should podcasts be a separate tab or integrated into library?
- Should user be able to download episodes for offline listening? (adds complexity)
- Max number of subscribed podcasts before pagination needed?
- Should we show play count, completion status per episode?
- Auto-refresh subscribed feeds on app launch, or manual refresh button?

## Dependencies
- No new external dependencies required (use native `XMLParser` for RSS)
- Optional: `FeedKit` or similar if native parsing becomes unwieldy
- Optional: `Kingfisher` or similar for image caching (but URLSession cache works)

## File Structure
```
Vinyl/
  Podcast/
    PodcastSearch.swift       # iTunes API integration
    RSSFeedParser.swift       # RSS XML parsing
    PodcastModels.swift       # Data models
    PodcastView.swift         # Main podcast tab UI
    PodcastSearchView.swift    # Search results UI
    PodcastDetailsView.swift   # Podcast + episodes UI
    PodcastStorageManager.swift # UserDefaults/CoreData handling
```
