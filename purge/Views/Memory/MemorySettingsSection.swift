import AppKit
import SwiftUI

struct MemorySettingsSection: View {
    @ObservedObject var settings: MemorySettingsStore
    @ObservedObject var notifications: MemoryNotificationController
    let coordinator: MemoryCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            Text(memoryText("Memory")).font(AppStyle.Typography.sectionTitle)
            Picker(memoryText("Aggregate refresh"), selection: $settings.interval) {
                Text(memoryText("1 second")).tag(Double(1))
                Text(memoryText("2 seconds")).tag(Double(2))
            }
            Text(memoryText("Processes refresh every 5 seconds while Memory is visible. Background process polling is off."))
                .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            Toggle(memoryText("Show Memory in the menu bar"), isOn: $settings.showsMenuBar)
            Toggle(memoryText("Notify about sustained memory pressure"), isOn: Binding(
                get: { settings.notifications }, set: { coordinator.enableNotifications($0) }
            ))
            Picker(memoryText("Notification threshold (60 seconds)"), selection: $settings.threshold) {
                Text(memoryText("Warning")).tag(MemoryPressure.warning)
                Text(memoryText("Critical")).tag(MemoryPressure.critical)
            }.disabled(!settings.notifications)
            if notifications.permissionDenied {
                Text(memoryText("Notification permission is denied. Enable it in System Settings."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.statusCheckText)
                Button(memoryText("Open notification settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.purge(.secondary))
            }
            Text(memoryText("Excluded from Memory actions")).font(AppStyle.Typography.headline)
            if settings.exclusions.isEmpty {
                Text(memoryText("No excluded applications.")).font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
            }
            ForEach(settings.exclusions.sorted(), id: \.self) { bundle in
                HStack {
                    Text(bundle).font(AppStyle.Typography.body)
                    Spacer()
                    Button(memoryText("Remove exclusion")) { settings.include(bundle) }
                        .buttonStyle(.purge(.secondary))
                }
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
        .task { await notifications.refreshPermission() }
    }
}
