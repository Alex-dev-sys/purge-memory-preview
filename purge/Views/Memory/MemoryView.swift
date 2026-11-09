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
    static let sheetWidth: CGFloat = 520
}

struct MemoryView: View {
    @ObservedObject var model: MemoryCoordinator
    @State private var pageID = UUID()
    @State private var range: TimeInterval = 60
    @State private var showHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                pressureSummary
                memoryBreakdown
                chart
                HStack {
                    Text(memoryText("Applications and processes")).font(AppStyle.Typography.sectionTitle)
                    Spacer()
                    Button(memoryText("Memory history")) { showHistory = true }
                        .buttonStyle(.purge(.secondary))
                }
                MemoryProcessListView(source: model.processStore, actions: model.actions,
                                      settings: model.settings, total: model.snapshot?.total)
            }
            .padding(AppStyle.Spacing.large)
        }
        .background(AppColors.surfaceBase)
        .background(MemoryWindowReader { model.page(pageID, window: $0) })
        .onDisappear { model.page(pageID, window: nil) }
        .sheet(isPresented: $showHistory) { MemoryHistoryView(history: model.history) }
    }

    private var pressureSummary: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Label(memoryText("Memory Pressure"), systemImage: "memorychip")
                    .font(AppStyle.Typography.sectionTitle)
                Spacer()
                Text(model.pressure.title).font(AppStyle.Typography.sectionTitle)
                    .foregroundStyle(model.pressure.color)
            }
            Text(memoryText("macOS manages memory automatically. Free RAM is not a health score."))
                .font(AppStyle.Typography.body).foregroundStyle(AppColors.textSecondary)
            if model.pressure == .unknown {
                Text(memoryText("Waiting for a pressure event. Silence does not mean Normal."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            if let date = model.snapshot?.sampledAt {
                HStack {
                    Text(model.statsUnavailable ? memoryText("Stale reading") : memoryText("Sampled"))
                    Text(date, style: .relative)
                }.font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            } else {
                Text(model.statsUnavailable ? memoryText("Unavailable") : memoryText("Reading memory…"))
                    .font(AppStyle.Typography.body)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
        .accessibilityElement(children: .combine)
    }

    private var memoryBreakdown: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            if let snapshot = model.snapshot, let remainder = snapshot.breakdownRemainder {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        segment(snapshot.app, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.appCaches)
                        segment(snapshot.wired, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.devTools)
                        segment(snapshot.compressed, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.largeFiles)
                        segment(snapshot.cached, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.apps)
                        segment(snapshot.free, total: snapshot.total, width: geometry.size.width, color: AppColors.Chart.freeSpace)
                        segment(remainder, total: snapshot.total, width: geometry.size.width, color: AppColors.fillSecondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.xs))
                }
                .frame(height: AppStyle.Spacing.small)
                .accessibilityLabel(memoryText("Estimated memory breakdown"))
                if remainder > 0 {
                    Text(memoryText("The neutral remainder is not accounted for by these estimates."))
                        .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                }
            } else {
                Text(memoryText("Breakdown unavailable. Valid individual readings are shown below."))
                    .font(AppStyle.Typography.callout).foregroundStyle(AppColors.textSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                      alignment: .leading, spacing: AppStyle.Spacing.medium) {
                metric(memoryText("Total"), model.snapshot?.total)
                metric(memoryText("Used (estimate)"), model.snapshot?.used)
                metric(memoryText("Free"), model.snapshot?.free)
                metric(memoryText("App Memory (estimate)"), model.snapshot?.app)
                metric(memoryText("Wired"), model.snapshot?.wired)
                metric(memoryText("Compressed"), model.snapshot?.compressed)
                metric(memoryText("Cached Files (estimate)"), model.snapshot?.cached)
                metric(memoryText("Swap Used"), model.snapshot?.swap)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
    }
    private func segment(_ bytes: Int64?, total: Int64, width: CGFloat, color: Color) -> some View {
        color.frame(width: width * CGFloat(bytes ?? 0) / CGFloat(max(total, 1)))
    }
    private func metric(_ title: String, _ bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
            Text(title).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            Text(MemoryFormat.bytes(bytes)).font(AppStyle.Typography.headline.numbers).monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }.accessibilityElement(children: .combine)
    }
    private var chart: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Picker(memoryText("Graph range"), selection: $range) {
                Text(memoryText("60 seconds")).tag(TimeInterval(60))
                Text(memoryText("5 minutes")).tag(TimeInterval(300))
                Text(memoryText("1 hour")).tag(TimeInterval(3600))
            }.pickerStyle(.segmented)
            let points = chartPoints
            Chart(points, id: \.sample.id) { point in
                if let used = point.sample.used {
                    LineMark(x: .value(memoryText("Time"), point.sample.sampledAt),
                             y: .value(memoryText("Used (estimate)"), used),
                             series: .value(memoryText("Observation segment"), point.segment))
                        .foregroundStyle(AppColors.Chart.devTools)
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-range)...Date())
            .chartYScale(domain: Int64(0)...max(model.snapshot?.total ?? 1, 1))
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let bytes = value.as(Int64.self) {
                            Text(MemoryFormat.bytes(bytes)).font(AppStyle.Typography.metadata.numbers)
                        }
                    }
                }
            }
            .frame(height: MemoryLayout.chartHeight)
            .accessibilityLabel(memoryText("Estimated used memory over time. Gaps indicate missing observations."))
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
            Text(model.pressure.title)
        }
        .accessibilityLabel(memoryText("Memory"))
        .onAppear { AppWindowPresenter.registerOpenWindowAction(openWindow) }
    }
}

struct MemoryMenuContent: View {
    @ObservedObject var model: MemoryCoordinator
    var body: some View {
        Text(model.pressure.title)
        Text(MemoryFormat.bytes(model.snapshot?.used))
        if model.statsUnavailable { Text(memoryText("Stale reading")) }
        Button(memoryText("Open Memory")) { model.openMemory() }
    }
}
