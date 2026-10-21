// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A model FutureT can complete text with. Base (not chat-tuned) models continue text naturally,
/// so they are preferred; the catalog is open, any mlx-community repo id can be added by the user.
public struct ModelChoice: Identifiable, Equatable, Codable, Sendable {
    public var id: String { repo }
    public let repo: String
    public let title: String
    /// Approximate size on disk and in memory once loaded, in GB (4-bit).
    public let sizeGB: Double
    /// Unified memory the Mac should have for this to run comfortably next to other apps.
    public let minMemoryGB: Int
    public let note: String

    public init(repo: String, title: String, sizeGB: Double, minMemoryGB: Int, note: String) {
        self.repo = repo; self.title = title; self.sizeGB = sizeGB; self.minMemoryGB = minMemoryGB; self.note = note
    }
}

public enum ModelCatalog {
    /// Candidates the bench mode compares. The default is picked from measurements, see `recommended`.
    public static let all: [ModelChoice] = [
        ModelChoice(repo: "mlx-community/gemma-3-270m-4bit", title: "Gemma 3 270M", sizeGB: 0.2, minMemoryGB: 8, note: "Tiny and instant, short completions"),
        ModelChoice(repo: "mlx-community/gemma-3-1b-pt-4bit", title: "Gemma 3 1B", sizeGB: 0.8, minMemoryGB: 8, note: "Fast, good everyday quality"),
        ModelChoice(repo: "mlx-community/Qwen2.5-1.5B-4bit", title: "Qwen 2.5 1.5B", sizeGB: 1.0, minMemoryGB: 8, note: "Fast, strong multilingual base"),
        ModelChoice(repo: "mlx-community/Qwen3-1.7B-4bit", title: "Qwen 3 1.7B", sizeGB: 1.1, minMemoryGB: 8, note: "Newer Qwen, small"),
        ModelChoice(repo: "mlx-community/gemma-3-4b-pt-4bit", title: "Gemma 3 4B", sizeGB: 2.6, minMemoryGB: 16, note: "Best quality that is still quick"),
        ModelChoice(repo: "mlx-community/Qwen3-4B-4bit", title: "Qwen 3 4B", sizeGB: 2.4, minMemoryGB: 16, note: "Higher quality, a little slower"),
    ]

    /// The model offered first. Chosen from `futuret-cli bench` on an M4 Max: Qwen 2.5 1.5B had the best mix of
    /// speed (about 140 ms a sentence, 70 ms while typing) and memory (1.3 GB). Bigger Macs may pick a larger one.
    public static func recommended(memoryBytes: UInt64) -> ModelChoice {
        let gb = Int(memoryBytes / 1_073_741_824)
        let pick = gb >= 32 ? "mlx-community/gemma-3-4b-pt-4bit" : "mlx-community/Qwen2.5-1.5B-4bit"
        return all.first { $0.repo == pick && $0.minMemoryGB <= gb } ?? all.first { $0.repo == "mlx-community/Qwen2.5-1.5B-4bit" }!
    }
}
