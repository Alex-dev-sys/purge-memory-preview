import SwiftUI

struct MemoryCleaningControls: View {
    @ObservedObject var cleanup: MemoryCleanupService
    @ObservedObject var settings: MemorySettingsStore
    @ObservedObject var actions: MemoryActionService
    @EnvironmentObject private var store: PurgeStore
    var showsBackground = true

    private var blocked: Bool {
        cleanup.isBusy || cleanup.isAuthorizing || actions.isBusy || store.isAnyCleanInProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            HStack {
                Text(memoryText("Memory cleaning")).font(AppStyle.Typography.sectionTitle)
                Spacer()
                Button {
                    Task { await cleanup.clean() }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        if cleanup.isBusy || cleanup.isAuthorizing {
                            ProgressView().controlSize(.small)
                        }
                        Text(cleanup.isAuthorizing ? memoryText("Waiting for approval…")
                             : cleanup.isBusy ? memoryText("Cleaning memory…") : memoryText("Clean Memory"))
                    }
                }
                .buttonStyle(.purge(.primary))
                .disabled(blocked)
            }
            Text(memoryText("Releases reclaimable system file cache. Applications stay open; their working memory is not cleared."))
                .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            if !cleanup.isEnabled {
                Text(memoryText("First use asks for administrator approval to enable a dedicated cache-cleaning service. Your password is not stored."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            if let message = cleanup.message {
                Text(message).font(AppStyle.Typography.body)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let before = cleanup.lastBeforeFree, let after = cleanup.lastAfterFree {
                Text(memoryText("Free RAM: \(MemoryFormat.bytes(before)) → \(MemoryFormat.bytes(after))"))
                    .font(AppStyle.Typography.metadata.numbers).foregroundStyle(AppColors.textSecondary)
            }
            Toggle(memoryText("Automatic memory cleaning"), isOn: Binding(
                get: { settings.automaticCleaning },
                set: { enabled in Task { await cleanup.setAutomatic(enabled) } }
            )).disabled(blocked)

            if settings.automaticCleaning {
                Picker(memoryText("Clean memory when"), selection: $settings.cleaningMode) {
                    ForEach(MemoryCleanupMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.disabled(blocked)
                if settings.cleaningMode == .timer {
                    Picker(memoryText("Cleaning interval"), selection: $settings.cleaningInterval) {
                        ForEach(MemorySettingsStore.cleanupIntervals, id: \.self) { minutes in
                            Text(memoryText("Every \(minutes.formatted()) minutes")).tag(minutes)
                        }
                    }.disabled(blocked)
                    if let next = cleanup.nextDate {
                        HStack {
                            Text(memoryText("Next memory cleaning"))
                            Text(next, style: .time)
                        }.font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    Picker(memoryText("Used RAM threshold"), selection: $settings.cleaningThreshold) {
                        ForEach(MemorySettingsStore.cleanupThresholds, id: \.self) { percent in
                            Text(verbatim: "\(percent)%").tag(percent)
                        }
                    }.disabled(blocked)
                    Text(memoryText("The threshold must hold for 30 seconds. After a cleanup, usage must fall 5 percentage points before another threshold cleanup."))
                        .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                }
                Text(memoryText("Runs while Purge is open, including menu bar mode. Pauses during sleep. Automatic cleanups are at least 5 minutes apart."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            Text(memoryText("macOS controls RAM allocation. A target usage level is not guaranteed; the measured free-RAM change can be zero."))
                .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            if cleanup.isEnabled {
                Button(memoryText("Remove memory cleaning permission")) {
                    Task { await cleanup.disable() }
                }.buttonStyle(.purge(.quiet, size: .small)).disabled(blocked)
            }
        }
        .padding(showsBackground ? AppStyle.Spacing.medium : 0)
        .background(showsBackground ? AppColors.surfaceCard : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
        .task { await cleanup.refreshPermission() }
    }
}
