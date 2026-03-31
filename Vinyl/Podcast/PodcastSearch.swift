import Foundation

class PodcastSearcher: ObservableObject {
    @Published var results: [PodcastSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private var searchTask: URLSessionDataTask?

    func search(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&entity=podcast&limit=25"
        guard let url = URL(string: urlString) else {
            isSearching = false
            errorMessage = "Invalid search query"
            return
        }

        searchTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSearching = false

                if let error = error as NSError?, error.code == NSURLErrorCancelled { return }

                if let error = error {
                    self?.errorMessage = "Search failed: \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)
                    // Filter out results without feed URLs
                    self?.results = decoded.results.filter { !$0.feedURL.isEmpty }
                } catch {
                    self?.errorMessage = "Failed to parse results"
                    print("Podcast search decode error: \(error)")
                }
            }
        }
        searchTask?.resume()
    }

    func cancel() {
        searchTask?.cancel()
        isSearching = false
    }
}
