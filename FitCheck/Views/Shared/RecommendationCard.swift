import SwiftUI
import UIKit

struct RecommendationCard: View {
    var recommendation: OutfitRecommendation
    var primaryTitle: String?
    var onPrimary: (() -> Void)?
    var onGood: (() -> Void)?
    var onBad: (() -> Void)?
    var onFeedback: (() -> Void)?
    var aiReview: AIOutfitResponse? = nil
    var aiReviewError: String? = nil
    var isAIReviewing = false
    var onAIReview: (() -> Void)?
    var avatarPreviewData: Data? = nil
    var avatarPreviewError: String? = nil
    var isGeneratingAvatarPreview = false
    var onAvatarPreview: (() -> Void)? = nil

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

            if let avatarPreviewData {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Avatar Preview", systemImage: "person.crop.rectangle")
                        .font(.caption.weight(.semibold))
                    FitCheckPhotoPreview(data: avatarPreviewData, height: 360)
                }
            } else if let avatarPreviewError {
                Label(avatarPreviewError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let primaryTitle, let onPrimary {
                    Button(action: onPrimary) {
                        Label(primaryTitle, systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    if let onAIReview {
                        if isAIReviewing {
                            FitCheckButtonLabel(
                                title: "Reviewing",
                                systemImage: "sparkles",
                                isLoading: true
                            )
                        } else {
                            Button(action: onAIReview) {
                                Label("AI Review", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let onAvatarPreview {
                        if isGeneratingAvatarPreview {
                            FitCheckButtonLabel(
                                title: "Generating Preview",
                                systemImage: "person.crop.rectangle",
                                isLoading: true
                            )
                        } else {
                            Button(action: onAvatarPreview) {
                                Label("Try On Avatar", systemImage: "person.crop.rectangle")
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
                    if let onFeedback {
                        Button(action: onFeedback) {
                            Label("Feedback", systemImage: "text.bubble")
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

struct OutfitFeedbackEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
    var initialType: FeedbackType = .badOutfit
    var onSave: (FeedbackType, String) -> Void

    @State private var selectedType: FeedbackType
    @State private var note = ""

    init(
        title: String,
        initialType: FeedbackType = .badOutfit,
        onSave: @escaping (FeedbackType, String) -> Void
    ) {
        self.title = title
        self.initialType = initialType
        self.onSave = onSave
        _selectedType = State(initialValue: initialType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(FeedbackType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should FitCheck remember?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $note)
                            .frame(minHeight: 120)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedType, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}
