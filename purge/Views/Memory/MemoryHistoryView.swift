import SwiftUI

struct MemoryHistoryView: View {
    @ObservedObject var history: MemoryHistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var clearConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            HStack {
                Text(memoryText("Memory history")).font(AppStyle.Typography.pageTitle)
                Spacer()
                Button(memoryText("Done")) { dismiss() }.buttonStyle(.purge(.secondary))
            }
            if history.isUnavailable {
                Text(memoryText("History is unavailable. The existing archive was preserved; monitoring can continue."))
                    .font(AppStyle.Typography.body).foregroundStyle(AppColors.statusCheckText)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    ForEach(history.entries) { entry in
                        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                            HStack {
                                Text(entry.name).font(AppStyle.Typography.headline)
                                Spacer()
                                Text(entry.action.title).font(AppStyle.Typography.body)
                            }
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                            Text(entry.outcome.title).font(AppStyle.Typography.body)
                            switch entry.measurement {
                            case .observed:
                                if let delta = entry.delta {
                                    Text(memoryText("Observed system-wide Used change (before − after): \(MemoryFormat.bytes(delta))"))
                                        .font(AppStyle.Typography.callout)
                                }
                            case .belowThreshold:
                                Text(memoryText("System-wide change below the reporting threshold."))
                                    .font(AppStyle.Typography.callout)
                            case .unmeasured:
                                Text(memoryText("System-wide change was not measured."))
                                    .font(AppStyle.Typography.callout)
                            }
                        }
                        .padding(AppStyle.Spacing.medium)
                        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.md))
                    }
                    if history.entries.isEmpty && !history.isUnavailable {
                        Text(memoryText("No Memory actions recorded.")).font(AppStyle.Typography.body)
                    }
                }
            }
            Button(memoryText("Clear Memory history")) { clearConfirmation = true }
                .buttonStyle(.purge(.secondary))
        }
        .padding(AppStyle.Spacing.large).frame(width: 600, height: 500)
        .background(AppColors.surfaceBase)
        .task { await history.load() }
        .confirmationDialog(memoryText("Clear all Memory action history?"), isPresented: $clearConfirmation) {
            Button(memoryText("Clear Memory history"), role: .destructive) { Task { await history.clear() } }
            Button(memoryText("Cancel"), role: .cancel) { }
        }
    }
}
