import AppKit
import QuickLookUI

@MainActor
enum QuickLookPreview {
    private static let dataSource = DataSource()

    static func show(url: URL) {
        dataSource.url = url.standardizedFileURL
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = dataSource
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class DataSource: NSObject, QLPreviewPanelDataSource {
    var url = URL(fileURLWithPath: "/")

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }
}
