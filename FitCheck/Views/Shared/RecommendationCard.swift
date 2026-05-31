import SwiftUI
import UIKit

struct RecommendationCard: View {
    var recommendation: OutfitRecommendation
    var primaryTitle: String?
    var onPrimary: (() -> Void)?
    var onGood: (() -> Void)?
    var onBad: (() -> Void)?
    var onFeedback: (() -> Void)?
    var onEdit: (() -> Void)?
    var aiReview: AIOutfitResponse? = nil
    var aiReviewError: String? = nil
    var isAIReviewing = false
    var onAIReview: (() -> Void)?
    var avatarPreviewData: Data? = nil
    var avatarPreviewError: String? = nil
    var isGeneratingAvatarPreview = false
    var onAvatarPreview: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(itemSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                scoreBadge
            }

            VStack(spacing: 8) {
                ForEach(recommendation.items) { item in
                    RecommendationItemRow(item: item)
                }
            }

            if !recommendation.notes.isEmpty {
                DisclosureGroup("Why this scored this way") {
                    ForEach(recommendation.notes, id: \.self) { note in
                        Label(note, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    FitCheckSaveImageButton(data: avatarPreviewData, title: "Save Preview to Photos")
                }
            } else if let avatarPreviewError {
                Label(avatarPreviewError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let primaryTitle, let onPrimary {
                    Button(action: onPrimary) {
                        Label(primaryTitle, systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: actionColumns, alignment: .center, spacing: 8) {
                    if let onAIReview {
                        actionButton(
                            title: isAIReviewing ? "Reviewing" : "AI",
                            systemImage: "sparkles",
                            isLoading: isAIReviewing,
                            action: onAIReview
                        )
                        .disabled(isAIReviewing)
                    }

                    if let onAvatarPreview {
                        actionButton(
                            title: isGeneratingAvatarPreview ? "Previewing" : "Avatar",
                            systemImage: "person.crop.rectangle",
                            isLoading: isGeneratingAvatarPreview,
                            action: onAvatarPreview
                        )
                        .disabled(isGeneratingAvatarPreview)
                    }

                    if let onGood {
                        actionButton(title: "Liked", systemImage: "hand.thumbsup", action: onGood)
                    }
                    if let onBad {
                        actionButton(title: "Reject", systemImage: "hand.thumbsdown", action: onBad)
                    }
                    if let onFeedback {
                        actionButton(title: "Feedback", systemImage: "text.bubble", action: onFeedback)
                    }
                    if let onEdit {
                        actionButton(title: "Edit", systemImage: "slider.horizontal.3", action: onEdit)
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var scoreBadge: some View {
        VStack(spacing: 2) {
            Text("\(Int(recommendation.score))")
                .font(.headline.monospacedDigit().weight(.semibold))
            Text("score")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(scoreTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(scoreTint)
        .accessibilityLabel("Score \(Int(recommendation.score))")
    }

    private var scoreTint: Color {
        if recommendation.score >= 75 {
            return .green
        }
        if recommendation.score >= 0 {
            return .orange
        }
        return .red
    }

    private var itemSummary: String {
        let categories = recommendation.items.map(\.category.displayName)
        guard !categories.isEmpty else { return "No items" }
        return categories.joined(separator: " · ")
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FitCheckButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .center)]
    }
}

private struct RecommendationItemRow: View {
    var item: ClothingItem

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photoData = item.photoData, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: item.category.systemImageName)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var detailText: String {
        [
            item.category.displayName,
            item.brand.isEmpty ? nil : item.brand,
            item.quantity > 1 ? "Qty \(item.quantity)" : nil
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

struct RecommendationDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var closetItems: [ClothingItem]
    var feedback: [Feedback]
    var stylePreference: StylePreference?
    var request: RecommendationRequest
    var onSave: (OutfitRecommendation) -> Void

    @State private var recommendation: OutfitRecommendation
    @State private var searchText = ""
    @State private var status = ""

    private let engine = OutfitRecommendationEngine()

    init(
        recommendation: OutfitRecommendation,
        closetItems: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest,
        onSave: @escaping (OutfitRecommendation) -> Void
    ) {
        _recommendation = State(initialValue: recommendation)
        self.closetItems = closetItems
        self.feedback = feedback
        self.stylePreference = stylePreference
        self.request = request
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Outfit") {
                    ForEach(recommendation.items) { item in
                        HStack {
                            Label(item.name, systemImage: item.category.systemImageName)
                            Spacer()
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Add Item") {
                    TextField("Search closet", text: $searchText)
                        .textInputAutocapitalization(.words)
                    ForEach(Array(addableItems.prefix(30))) { item in
                        Button {
                            add(item)
                        } label: {
                            HStack {
                                Label(item.name, systemImage: item.category.systemImageName)
                                Spacer()
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Score") {
                    Text("Score \(Int(recommendation.score))")
                        .font(.headline)
                    if !recommendation.notes.isEmpty {
                        DisclosureGroup("Why this scored this way") {
                            ForEach(recommendation.notes, id: \.self) { note in
                                Label(note, systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Outfit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(recommendation)
                        dismiss()
                    }
                }
            }
        }
    }

    private var addableItems: [ClothingItem] {
        let selectedIDs = Set(recommendation.items.map(\.id))
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return closetItems
            .filter { $0.status == .active && !selectedIDs.contains($0.id) }
            .filter { search.isEmpty || searchableText(for: $0).localizedCaseInsensitiveContains(search) }
            .sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return categorySortIndex($0.category) < categorySortIndex($1.category)
            }
    }

    private func add(_ item: ClothingItem) {
        recommendation.items.append(item)
        rescore(message: "Added \(item.name).")
    }

    private func remove(_ item: ClothingItem) {
        recommendation.items.removeAll { $0.id == item.id }
        rescore(message: "Removed \(item.name).")
    }

    private func rescore(message: String) {
        let originalID = recommendation.id
        var updated = engine.scoreExistingOutfit(
            items: recommendation.items,
            feedback: feedback,
            stylePreference: stylePreference,
            request: request,
            title: recommendation.title
        )
        updated.id = originalID
        recommendation = updated
        status = "\(message) Score updated."
    }

    private func searchableText(for item: ClothingItem) -> String {
        [
            item.name,
            item.brand,
            item.category.displayName,
            ClothingInference.color(for: item),
            ClothingInference.pattern(for: item),
            item.notes
        ]
        .joined(separator: " ")
    }

    private func categorySortIndex(_ category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
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
