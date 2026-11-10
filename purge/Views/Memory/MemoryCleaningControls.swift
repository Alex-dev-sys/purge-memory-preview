import SwiftUI

struct MemoryCleaningControls: View {
    @ObservedObject var cleanup: MemoryCleanupService
    @ObservedObject var settings: MemorySettingsStore
    @ObservedObject var actions: MemoryActionService
    @EnvironmentObject private var store: PurgeStore
    @State private var showInformation = false
    var showsBackground = true

    private var blocked: Bool {
        cleanup.isBusy || cleanup.isAuthorizing || actions.isBusy || store.isAnyCleanInProgress
    }

    var body: some View {
        Group {
            if showsBackground { content.overviewCard() }
            else { content }
        }
        .task { await cleanup.refreshPermission() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            HStack(spacing: AppStyle.Spacing.small) {
                Image(systemName: "memorychip")
                    .font(AppStyle.Typography.sectionTitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: AppStyle.IconTile.size, height: AppStyle.IconTile.size)
                    .background(AppColors.fillSecondary,
                                in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                        Text(memoryText("Memory cleaning")).font(AppStyle.Typography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        informationButton
                    }
                    Text(memoryText("Free up reclaimable cache."))
                        .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Button {
                    Task { await cleanup.clean() }
                } label: {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        if cleanup.isBusy || cleanup.isAuthorizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(cleanup.isAuthorizing ? memoryText("Waiting for approval…")
                             : cleanup.isBusy ? memoryText("Cleaning memory…") : memoryText("Clean Memory"))
                    }
                }
                .buttonStyle(.purge(.primary))
                .fixedSize()
                .disabled(blocked)
            }

            if !cleanup.isEnabled {
                Label(memoryText("Administrator approval on first use"), systemImage: "lock")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textTertiary)
            }

            if let message = cleanup.message {
                HStack(alignment: .top, spacing: AppStyle.Spacing.xSmall) {
                    Image(systemName: cleanup.lastBeforeFree == nil ? "info.circle" : "checkmark.circle")
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                        Text(message).font(AppStyle.Typography.callout)
                            .accessibilityAddTraits(.updatesFrequently)
                        if let before = cleanup.lastBeforeFree, let after = cleanup.lastAfterFree {
                            Text(memoryText("Free RAM: \(MemoryFormat.bytes(before)) → \(MemoryFormat.bytes(after))"))
                                .font(AppStyle.Typography.metadata.numbers)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(AppStyle.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.fillSecondary,
                            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md))
            }

            Rectangle().fill(AppColors.borderSubtle).frame(height: 1)

            HStack(spacing: AppStyle.Spacing.small) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(memoryText("Auto-clean")).font(AppStyle.Typography.rowTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(automaticCaption).font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Toggle(memoryText("Automatic memory cleaning"), isOn: Binding(
                    get: { settings.automaticCleaning },
                    set: { enabled in Task { await cleanup.setAutomatic(enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppColors.statusSafeText)
                .disabled(blocked)
            }

            if settings.automaticCleaning {
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    SettingsMenuPicker(selection: $settings.cleaningMode,
                        options: MemoryCleanupMode.allCases, optionLabel: \.title,
                        accessibilityTitle: memoryText("Clean memory when"))
                    if settings.cleaningMode == .timer {
                        SettingsMenuPicker(selection: $settings.cleaningInterval,
                            options: MemorySettingsStore.cleanupIntervals,
                            optionLabel: { memoryText("Every \($0.formatted()) minutes") },
                            accessibilityTitle: memoryText("Cleaning interval"))
                    } else {
                        SettingsMenuPicker(selection: $settings.cleaningThreshold,
                            options: MemorySettingsStore.cleanupThresholds,
                            optionLabel: { (Double($0) / 100).formatted(.percent.precision(.fractionLength(0))) },
                            accessibilityTitle: memoryText("Used RAM threshold"))
                    }
                    Spacer(minLength: 0)
                }
                .disabled(blocked)

                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    if settings.cleaningMode == .timer, let next = cleanup.nextDate {
                        Image(systemName: "clock")
                        Text(memoryText("Next memory cleaning"))
                        Text(next, style: .time)
                    } else {
                        Text(memoryText("Above the threshold for 30 seconds"))
                    }
                    Spacer(minLength: 0)
                }
                .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(showsBackground ? AppStyle.Spacing.medium : 0)
    }

    private var automaticCaption: String {
        guard settings.automaticCleaning else { return memoryText("Manual cleaning only") }
        if settings.cleaningMode == .timer {
            return memoryText("Every \(settings.cleaningInterval.formatted()) minutes")
        }
        let threshold = (Double(settings.cleaningThreshold) / 100).formatted(.percent.precision(.fractionLength(0)))
        return memoryText("At \(threshold) RAM usage")
    }

    private var informationButton: some View {
        Button { showInformation.toggle() } label: {
            Image(systemName: "info.circle")
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textTertiary)
        }
        .buttonStyle(.plain)
        .help(memoryText("How memory cleaning works"))
        .accessibilityLabel(memoryText("How memory cleaning works"))
        .popover(isPresented: $showInformation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                Text(memoryText("Memory cleaning")).font(AppStyle.Typography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(memoryText("Releases reclaimable system file cache. Applications stay open; their working memory is not cleared."))
                if !cleanup.isEnabled {
                    Text(memoryText("First use asks for administrator approval to enable a dedicated cache-cleaning service. Your password is not stored."))
                }
                Text(memoryText("macOS controls RAM allocation. A target usage level is not guaranteed; the measured free-RAM change can be zero."))
                Text(memoryText("Runs while Purge is open, including menu bar mode. Pauses during sleep. Automatic cleanups are at least 5 minutes apart."))
                Text(memoryText("The threshold must hold for 30 seconds. After a cleanup, usage must fall 5 percentage points before another threshold cleanup."))
                if cleanup.isEnabled {
                    Button(memoryText("Remove memory cleaning permission")) {
                        showInformation = false
                        Task { await cleanup.disable() }
                    }.buttonStyle(.purge(.secondary, size: .small)).disabled(blocked)
                }
            }
            .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            .padding(AppStyle.Spacing.medium).frame(width: 360)
        }
    }
}
