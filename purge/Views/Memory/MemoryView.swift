import AppKit
import Charts
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

private enum MemoryLayout {
    static let chartHeight: CGFloat = 140 // Fixed plot geometry, not spacing.
}

struct MemoryView: View {
    @ObservedObject var model: MemoryCoordinator
    @State private var pageID = UUID()
    @State private var range: TimeInterval = 60
    @State private var showHistory = false
    @State private var showReadingInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                summary
                MemoryCleaningControls(cleanup: model.cleanup, settings: model.settings, actions: model.actions)
                activityCard
                applications
            }
            .padding(.horizontal, AppDetailPageLayout.horizontalInset)
            .padding(.top, AppStyle.Spacing.small)
            .padding(.bottom, AppStyle.Spacing.large)
        }
        .background(AppColors.surfaceBase)
        .background(MemoryWindowReader { model.page(pageID, window: $0) })
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
                    segment(snapshot.app, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.appCaches)
                    segment(snapshot.wired, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.devTools)
                    segment(snapshot.compressed, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.largeFiles)
                    segment(snapshot.cached, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.apps)
                    segment(snapshot.free, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.freeSpace)
                    segment(remainder, total: snapshot.total, width: geometry.size.width, color: AppColors.fillSecondary)
                }
            } else {
                AppColors.fillSecondary
            }
        }
        .frame(height: AppStyle.Spacing.xSmall)
        .clipShape(Capsule())
        .accessibilityLabel(memoryText("Estimated memory breakdown"))
    }

    private func segment(_ bytes: Int64?, total: Int64, width: CGFloat, color: Color) -> some View {
        color.frame(width: width * CGFloat(bytes ?? 0) / CGFloat(max(total, 1)))
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            HStack(spacing: AppStyle.Spacing.small) {
                Text(memoryText("Memory activity")).font(AppStyle.Typography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppStyle.Spacing.small)
                SettingsMenuPicker(selection: $range, options: [TimeInterval(60), 300, 3600],
                    optionLabel: { value in
                        value == 60 ? memoryText("60 seconds") : value == 300 ? memoryText("5 minutes") : memoryText("1 hour")
                    }, accessibilityTitle: memoryText("Graph range"))
            }
            chart
            Rectangle().fill(AppColors.borderSubtle).frame(height: 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 5),
                      alignment: .leading, spacing: AppStyle.Spacing.medium) {
                metric(memoryText("Applications"), model.snapshot?.app, color: AppColors.Chart.appCaches,
                       help: memoryText("App Memory (estimate)"))
                metric(memoryText("System"), model.snapshot?.wired, color: AppColors.Chart.devTools,
                       help: memoryText("Wired memory reserved by macOS."))
                metric(memoryText("Compressed"), model.snapshot?.compressed, color: AppColors.Chart.largeFiles,
                       help: memoryText("Compressed"))
                metric(memoryText("File cache"), model.snapshot?.cached, color: AppColors.Chart.apps,
                       help: memoryText("Cached Files (estimate)"))
                metric(memoryText("Swap"), model.snapshot?.swap, color: nil,
                       help: memoryText("Swap Used"))
            }
            if model.statsUnavailable {
                Text(memoryText("Stale reading")).font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.statusCheckText)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .overviewCard()
    }

    private func metric(_ title: String, _ bytes: Int64?, color: Color?, help: String) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                if let color {
                    Circle().fill(color).frame(width: AppStyle.Spacing.xxSmallPlus, height: AppStyle.Spacing.xxSmallPlus)
                }
                Text(title).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Text(MemoryFormat.bytes(bytes)).font(AppStyle.Typography.sectionTitle.numbers)
                .foregroundStyle(AppColors.textPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .help(help).accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let now = Date()
        let points = chartPoints
        let total = max(model.snapshot?.total ?? 1, 1)
        return Chart(points, id: \.sample.id) { point in
            if let used = point.sample.used {
                AreaMark(x: .value(memoryText("Time"), point.sample.sampledAt),
                         y: .value(memoryText("Used (estimate)"), used),
                         series: .value(memoryText("Observation segment"), point.segment), stacking: .unstacked)
                    .foregroundStyle(LinearGradient(colors: [AppColors.Chart.devTools.opacity(0.18),
                                                             AppColors.Chart.devTools.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value(memoryText("Time"), point.sample.sampledAt),
                         y: .value(memoryText("Used (estimate)"), used),
                         series: .value(memoryText("Observation segment"), point.segment))
                    .foregroundStyle(AppColors.Chart.devTools)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: now.addingTimeInterval(-range)...now)
        .chartYScale(domain: Int64(0)...total)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel().font(AppStyle.Typography.metadata.font)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: total > 1 ? [Int64(0), total / 2, total] : []) { value in
                AxisGridLine().foregroundStyle(AppColors.borderSubtle)
                AxisValueLabel {
                    if let bytes = value.as(Int64.self) {
                        Text(MemoryFormat.bytes(bytes)).font(AppStyle.Typography.metadata.numbers)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
        }
        .frame(height: MemoryLayout.chartHeight)
        .overlay {
            if !points.contains(where: { $0.sample.used != nil }) {
                Text(model.statsUnavailable ? memoryText("Unavailable") : memoryText("Reading memory…"))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textTertiary)
            }
        }
        .accessibilityLabel(memoryText("Estimated used memory over time. Gaps indicate missing observations."))
    }

    private var applications: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                Text(memoryText("Applications and processes")).font(AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                Button { showHistory = true } label: {
                    Label(memoryText("Memory history"), systemImage: "clock.arrow.circlepath")
                }.buttonStyle(.purge(.secondary, size: .small))
            }
            MemoryProcessListView(source: model.processStore, actions: model.actions,
                                  settings: model.settings, total: model.snapshot?.total)
        }
    }

    private var chartPoints: [(sample: MemorySnapshot, segment: Int)] {
        var segment = 0
        var previous: MemoryChartEntry?
        return model.chart.entries.filter { $0.snapshot.sampledAt >= Date().addingTimeInterval(-range) }.map { entry in
            if entry.snapshot.used == nil { segment += 1; previous = nil; return (entry.snapshot, segment) }
            if let previous, previous.generation != entry.generation
                || entry.snapshot.sampledAt.timeIntervalSince(previous.snapshot.sampledAt) > max(entry.interval, previous.interval) * 1.5 {
                segment += 1
            }
            previous = entry
            return (entry.snapshot, segment)
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
