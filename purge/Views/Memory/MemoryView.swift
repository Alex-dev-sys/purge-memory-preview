import AppKit
import SwiftUI

extension MemoryPressure {
    var color: Color {
        switch self {
        case .unknown: AppColors.statusUnsureText
        case .normal: AppColors.statusSafeText
        case .warning: AppColors.statusCheckText
        case .critical: AppColors.statusDangerText
        }
    }
}

struct MemoryView: View {
    @ObservedObject var model: MemoryCoordinator
    @State private var pageID = UUID()
    @State private var showHistory = false
    @State private var applicationsExpanded = true
    @State private var showReadingInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                summary
                MemoryCleaningControls(cleanup: model.cleanup, settings: model.settings, actions: model.actions)
                applications
            }
            .padding(.horizontal, AppDetailPageLayout.horizontalInset)
            .padding(.top, AppStyle.Spacing.small)
            .padding(.bottom, AppStyle.Spacing.large)
        }
        .background(AppColors.surfaceBase)
        .background(MemoryWindowReader { model.page(pageID, window: $0, processesVisible: applicationsExpanded) })
        .onChange(of: applicationsExpanded) { model.processDetails(pageID, visible: $0) }
        .onDisappear { model.page(pageID, window: nil) }
        .sheet(isPresented: $showHistory) { MemoryHistoryView(history: model.history) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.medium) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        Text(memoryText("Used memory"))
                            .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                        if model.pressure != .unknown {
                            HStack(spacing: AppStyle.Spacing.xxSmall) {
                                Circle().fill(model.pressure.color)
                                    .frame(width: AppStyle.Spacing.xxSmallPlus, height: AppStyle.Spacing.xxSmallPlus)
                                Text(model.pressure.title).font(AppStyle.Typography.metadata)
                                    .foregroundStyle(model.pressure.color)
                            }
                            .accessibilityLabel(memoryText("Memory status") + ": " + model.pressure.title)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
                        Text(MemoryFormat.bytes(model.snapshot?.used))
                            .font(AppStyle.Typography.displaySmall.numbers)
                            .foregroundStyle(AppColors.textPrimary)
                            .overviewNumberTransition(model.snapshot?.used, reduceMotion: reduceMotion)
                            .lineLimit(1).minimumScaleFactor(0.65)
                        if let total = model.snapshot?.total {
                            Text(memoryText("of \(MemoryFormat.bytes(total))"))
                                .font(AppStyle.Typography.body.numbers)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: AppStyle.Spacing.small)
                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxSmall) {
                    Text(memoryText("Free")).font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(MemoryFormat.bytes(model.snapshot?.free))
                        .font(AppStyle.Typography.sectionTitle.numbers)
                        .foregroundStyle(AppColors.textPrimary)
                        .overviewNumberTransition(model.snapshot?.free, reduceMotion: reduceMotion)
                }
                .accessibilityElement(children: .combine)
            }
            memoryBar
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                if let date = model.snapshot?.sampledAt {
                    Text(model.statsUnavailable ? memoryText("Stale reading") : memoryText("Sampled"))
                    Text(date, style: .relative)
                } else {
                    Text(model.statsUnavailable ? memoryText("Unavailable") : memoryText("Reading memory…"))
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Button { showReadingInfo.toggle() } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(memoryText("About memory readings"))
                .accessibilityLabel(memoryText("About memory readings"))
                .popover(isPresented: $showReadingInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        Text(memoryText("Memory status")).font(AppStyle.Typography.headline)
                        Text(memoryText("macOS manages memory automatically. Free RAM is not a health score."))
                        Text(memoryText("The neutral remainder is not accounted for by these estimates."))
                        if model.pressure == .unknown {
                            Text(memoryText("macOS hasn't reported the memory state yet."))
                        }
                    }
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
                    .padding(AppStyle.Spacing.medium).frame(width: 320)
                }
            }
            .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textTertiary)
        }
    }

    private var memoryBar: some View {
        GeometryReader { geometry in
            if let snapshot = model.snapshot, let remainder = snapshot.breakdownRemainder {
                HStack(spacing: 0) {
                    segment(snapshot.app, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.appCaches, label: memoryText("Applications"))
                    segment(snapshot.wired, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.devTools, label: memoryText("System"))
                    segment(snapshot.compressed, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.largeFiles, label: memoryText("Compressed"))
                    segment(snapshot.cached, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.apps, label: memoryText("File cache"))
                    segment(snapshot.free, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.freeSpace, label: memoryText("Free"))
                    segment(remainder, total: snapshot.total, width: geometry.size.width, color: AppColors.fillSecondary, label: memoryText("The neutral remainder is not accounted for by these estimates."))
                }
            } else {
                AppColors.fillSecondary
            }
        }
        .frame(height: AppStyle.Spacing.xSmall)
        .clipShape(Capsule())
        .accessibilityLabel(memoryText("Estimated memory breakdown"))
    }

    private func segment(_ bytes: Int64?, total: Int64, width: CGFloat, color: Color, label: String) -> some View {
        color.frame(width: width * CGFloat(bytes ?? 0) / CGFloat(max(total, 1)))
            .help(label + ": " + MemoryFormat.bytes(bytes))
    }

    private var applications: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        applicationsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        Image(systemName: applicationsExpanded ? "chevron.down" : "chevron.right")
                            .font(AppStyle.Typography.metadata.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: AppStyle.Spacing.small)
                        Text(memoryText("Applications and processes")).font(AppStyle.Typography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(applicationsExpanded ? memoryText("Expanded") : memoryText("Collapsed"))
                Spacer(minLength: AppStyle.Spacing.small)
                Button { showHistory = true } label: {
                    Label(memoryText("Memory history"), systemImage: "clock.arrow.circlepath")
                }.buttonStyle(.purge(.secondary, size: .small))
            }
            if applicationsExpanded {
                MemoryProcessListView(source: model.processStore, actions: model.actions,
                                      settings: model.settings, total: model.snapshot?.total)
            }
        }
    }

}

private struct MemoryWindowReader: NSViewRepresentable {
    let changed: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.changed = changed; return view }
    func updateNSView(_ nsView: Reader, context: Context) { nsView.changed = changed }
    final class Reader: NSView {
        var changed: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [weak self] in self?.changed?(window) }
        }
    }
}

struct MemoryMenuLabel: View {
    @ObservedObject var model: MemoryCoordinator
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack {
            Image(systemName: "memorychip")
            Text(MemoryFormat.bytes(model.snapshot?.used))
            if model.pressure != .unknown {
                Text(model.pressure.title)
            }
        }
        .accessibilityLabel(memoryText("Memory"))
        .onAppear { AppWindowPresenter.registerOpenWindowAction(openWindow) }
    }
}

struct MemoryMenuContent: View {
    @ObservedObject var model: MemoryCoordinator
    var body: some View {
        if model.pressure != .unknown {
            Text(model.pressure.title)
        }
        Text(MemoryFormat.bytes(model.snapshot?.used))
        if model.statsUnavailable { Text(memoryText("Stale reading")) }
        Button(memoryText("Open Memory")) { model.openMemory() }
    }
}
