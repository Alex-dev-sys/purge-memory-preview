import AppKit
import SwiftUI

@MainActor
private enum MemoryIconCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>(); cache.countLimit = 256; return cache
    }()
    static func image(_ path: String) -> NSImage {
        if let image = images.object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        images.setObject(image, forKey: path as NSString)
        return image
    }
}

struct MemoryProcessListView: View {
    @ObservedObject var source: MemoryProcessStore
    @ObservedObject var actions: MemoryActionService
    @ObservedObject var settings: MemorySettingsStore
    let total: Int64?
    @State private var search = ""
    @State private var sortByName = false
    @State private var selected: Set<MemoryGroupIdentity> = []
    @State private var confirmation: MemoryConfirmation?

    var body: some View {
        let displayedGroups = groups
        return VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                CapsuleSearchField(query: $search,
                    prompt: LocalizedStringKey(memoryText("Search applications")),
                    accessibilityLabel: LocalizedStringKey(memoryText("Search applications or bundle identifiers")),
                    width: 260)
                Spacer(minLength: AppStyle.Spacing.small)
                SettingsMenuPicker(selection: $sortByName, options: [false, true],
                    optionLabel: { $0 ? memoryText("Name") : memoryText("Memory use") },
                    accessibilityTitle: memoryText("Sort"))
            }
            if !selected.isEmpty {
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    Text(memoryText("Selected: \(selected.count.formatted())"))
                        .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: AppStyle.Spacing.small)
                    Button(memoryText("Quit")) { prepare(action: .quit) }
                        .buttonStyle(.purge(.secondary, size: .small))
                        .disabled(actions.isBusy || source.unavailable)
                    Button(memoryText("Force Quit")) { prepare(action: .forceQuit) }
                        .buttonStyle(.purge(.secondary, size: .small))
                        .disabled(actions.isBusy || source.unavailable)
                }
            }
            if actions.isBusy {
                Text(memoryText("An action is running. Further requests are disabled."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            if let message = actions.message {
                Text(message).font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            if source.unavailable {
                Text(memoryText("Process readings are stale or unavailable. Actions are disabled."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.statusCheckText)
            }
            if source.sample?.isPartial == true {
                Text(memoryText("Some process counters are inaccessible. This list is partial."))
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            }
            if let sampled = source.sample?.sampledAt {
                HStack { Text(memoryText("Process sample")); Text(sampled, style: .relative) }
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(displayedGroups.enumerated()), id: \.element.id) { index, group in
                    let requestable = isRequestable(group)
                    if index > 0 {
                        Rectangle().fill(AppColors.borderSubtle).frame(height: 1)
                            .padding(.horizontal, AppStyle.Spacing.medium)
                    }
                    if index == 0 || requestable != isRequestable(displayedGroups[index - 1]) {
                        Label(requestable ? memoryText("Can be closed") : memoryText("Protected or unavailable"),
                              systemImage: requestable ? "app" : "lock")
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppStyle.Spacing.medium)
                            .padding(.top, AppStyle.Spacing.small)
                            .accessibilityAddTraits(.isHeader)
                    }
                    processRow(group)
                }
            }
            .overviewCard()
            if source.sample == nil && !source.unavailable {
                ProgressView(memoryText("Reading processes…"))
            } else if displayedGroups.isEmpty && !source.unavailable {
                Text(memoryText("No matching processes.")).font(AppStyle.Typography.body)
            }
        }
        .onChange(of: source.sample?.sampledAt) { _ in
            selected.formIntersection(Set((source.sample?.groups ?? []).map(\.id)))
        }
        .onDisappear {
            actions.foregroundEnded()
            actions.cancelConfirmation()
        }
        .sheet(item: $confirmation) { value in
            MemoryActionConfirmationView(confirmation: value, policy: actions.policy, exclusions: settings.exclusions) {
                confirmation = nil; actions.cancelConfirmation()
            } confirm: {
                confirmation = nil
                Task {
                    // Let the sheet dismissal finish before presenting a revised target list.
                    let revised = await actions.execute(token: value.id)
                    if let revised { confirmation = revised }
                    selected.removeAll()
                }
            }
        }
    }

    private var groups: [MemoryProcessGroup] {
        let filtered = (source.sample?.groups ?? []).filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
        }
        return MemoryProcessOrdering.sorted(filtered, policy: actions.policy, exclusions: settings.exclusions, byName: sortByName)
    }
    private func isRequestable(_ group: MemoryProcessGroup) -> Bool {
        MemoryProcessOrdering.isRequestable(group, policy: actions.policy, exclusions: settings.exclusions)
    }
    private func prepare(action: MemoryAction) {
        let targets = (source.sample?.groups ?? []).filter { selected.contains($0.id) }
        confirmation = actions.confirmation(targets, action: action)
    }
    private func processRow(_ group: MemoryProcessGroup) -> some View {
        let safety: MemorySafety = isRequestable(group) ? actions.policy.classify(group.root, exclusions: settings.exclusions) : .protected
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                Text(group.explanation).font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                Text(safety == .protected
                     ? memoryText("Actions are unavailable: identity, ownership, protection, counters or exclusions prevent this request.")
                     : memoryText("Eligible for a confirmed request. Unsaved work may exist; normal Quit preserves save prompts."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                ForEach(group.members) { member in
                    HStack {
                        Text(member.name)
                        Text(memoryText("PID \(member.identity.pid.formatted())")).monospacedDigit()
                        Spacer()
                        Text(MemoryFormat.bytes(member.footprint))
                    }.font(AppStyle.Typography.metadata)
                }
            }.padding(.top, AppStyle.Spacing.xSmall)
        } label: {
            HStack(spacing: AppStyle.Spacing.small) {
                Toggle(group.title, isOn: Binding(
                    get: { selected.contains(group.id) },
                    set: { if $0 { selected.insert(group.id) } else { selected.remove(group.id) } }
                )).labelsHidden().toggleStyle(.checkbox)
                    .disabled(source.unavailable || !actions.canAct(group))
                    .accessibilityLabel(group.title)
                if let path = group.root.app?.bundlePath {
                    Image(nsImage: MemoryIconCache.image(path)).resizable()
                        .frame(width: AppStyle.Row.listIconFrameSize, height: AppStyle.Row.listIconFrameSize)
                } else { Image(systemName: "gearshape").frame(width: AppStyle.Row.listIconFrameSize) }
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(group.title).font(AppStyle.Typography.rowTitle).lineLimit(1)
                    Text(safety.title).font(AppStyle.Typography.metadata)
                        .foregroundStyle(safety == .protected ? AppColors.textSecondary
                                         : safety == .safe ? AppColors.statusSafeText : AppColors.statusCheckText)
                }
                Spacer()
                Text(MemoryFormat.bytes(group.footprint)).font(AppStyle.Typography.headline.numbers).monospacedDigit()
                    .frame(minWidth: 72, alignment: .trailing)
                if let footprint = group.footprint, let total, total > 0 {
                    Text((Double(footprint) / Double(total)).formatted(.percent.precision(.fractionLength(1))))
                        .font(AppStyle.Typography.metadata.numbers).foregroundStyle(AppColors.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                } else {
                    Text(verbatim: "—").font(AppStyle.Typography.metadata.numbers)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
        .contextMenu {
            if let bundle = group.bundleID {
                Button(memoryText("Exclude from Memory actions")) { settings.exclude(bundle); selected.remove(group.id) }
            }
        }
    }
}

struct MemoryActionConfirmationView: View {
    let confirmation: MemoryConfirmation
    let policy: MemorySafetyPolicy
    let exclusions: Set<String>
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            Text(confirmation.action.title).font(AppStyle.Typography.pageTitle)
            Text(memoryText("Unsaved work may exist in every application, including those marked Safe to Quit."))
                .font(AppStyle.Typography.body)
            if confirmation.action == .forceQuit {
                Text(memoryText("Force Quit can permanently lose unsaved changes. It is separate from normal Quit."))
                    .font(AppStyle.Typography.headline).foregroundStyle(AppColors.statusDangerText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    ForEach(confirmation.targets) { target in
                        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                            HStack { Text(target.title); Spacer(); Text(MemoryFormat.bytes(target.footprint)) }
                            Text(target.sampledAt, style: .relative).font(AppStyle.Typography.metadata)
                            if policy.classify(target.root, exclusions: exclusions) == .checkFirst {
                                Text(memoryText("Check for unsaved documents and important background work."))
                                    .foregroundStyle(AppColors.statusCheckText)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 250)
            Text(memoryText("Sizes are sampled group footprints, not guaranteed memory release. Leaving Memory stops remaining requests."))
                .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            HStack {
                Spacer()
                Button(memoryText("Cancel"), action: cancel).buttonStyle(.purge(.secondary)).keyboardShortcut(.cancelAction)
                Button(confirmation.action.title, action: confirm)
                    .buttonStyle(.purge(confirmation.action == .forceQuit ? .destructive : .primary))
            }
        }.padding(AppStyle.Spacing.large).frame(width: 520)
    }
}
