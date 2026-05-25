import SwiftUI

struct RecommendationCard: View {
    var recommendation: OutfitRecommendation
    var primaryTitle: String?
    var onPrimary: (() -> Void)?
    var onGood: (() -> Void)?
    var onBad: (() -> Void)?
    var aiReview: AIOutfitResponse? = nil
    var aiReviewError: String? = nil
    var isAIReviewing = false
    var onAIReview: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text("Score \(Int(recommendation.score))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(recommendation.items) { item in
                HStack {
                    Image(systemName: iconName(for: item.category))
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                        Text(item.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if !recommendation.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.notes, id: \.self) { note in
                        Label(note, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let aiReview {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI Review", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                    Text(aiReview.rationale)
                        .font(.caption)
                    ForEach(aiReview.cautions, id: \.self) { caution in
                        Label(caution, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let aiReviewError {
                Label(aiReviewError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let primaryTitle, let onPrimary {
                        Button(action: onPrimary) {
                            Label(primaryTitle, systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let onAIReview {
                        if isAIReviewing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(action: onAIReview) {
                                Label("AI Review", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                HStack {
                    if let onGood {
                        Button(action: onGood) {
                            Label("Wore + Liked", systemImage: "hand.thumbsup")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let onBad {
                        Button(action: onBad) {
                            Label("Reject", systemImage: "hand.thumbsdown")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func iconName(for category: ClothingCategory) -> String {
        category.systemImageName
    }
}
