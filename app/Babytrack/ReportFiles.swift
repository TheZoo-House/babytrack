import BabyCore
import SwiftUI
import UIKit

struct ShareFile: Identifiable { let id = UUID(); var url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor enum ReportFiles {
    static func write(child: String, from: Date, through: Date, rows: [CareReportRow], format: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Care reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Care-report-" + UUID().uuidString + (format == "CSV" ? ".csv" : ".pdf"))
        if format == "CSV" { try Data(CareReports.csv(child: child, rows: rows).utf8).write(to: file, options: .atomic); return file }
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let font = UIFont.systemFont(ofSize: 11), heading = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let width: CGFloat = 507
        try renderer.writePDF(to: file) { context in
            var y: CGFloat = 90, page = 0
            func beginPage() {
                context.beginPage(); page += 1; y = 90
                (child + " care report").draw(at: CGPoint(x: 44, y: 30), withAttributes: [.font: heading, .foregroundColor: UIColor.black])
                (from.formatted(date: .abbreviated, time: .omitted) + " to " + through.formatted(date: .abbreviated, time: .omitted)).draw(at: CGPoint(x: 44, y: 58), withAttributes: [.font: font, .foregroundColor: UIColor.darkGray])
                ("Page \(page)").draw(at: CGPoint(x: 44, y: 812), withAttributes: [.font: font, .foregroundColor: UIColor.darkGray])
            }
            beginPage()
            for row in rows {
                let prefix = row.entity.date.formatted(date: .abbreviated, time: .shortened) + " · " + row.entity.title
                let notes = row.entity.fields["notes"] ?? ""
                let body = [prefix, row.detail, notes == row.detail ? "" : notes, "Recorded by " + row.entity.actor].filter { !$0.isEmpty }.joined(separator: "\n")
                let storage = NSTextStorage(string: body, attributes: [.font: font, .foregroundColor: UIColor.black])
                let layout = NSLayoutManager(); storage.addLayoutManager(layout)
                let height = ceil(body.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height) + 12
                if y + height > 790 && height <= 700 { beginPage() }
                var drawn = 0
                while drawn < layout.numberOfGlyphs {
                    if y > 760 { beginPage() }
                    let container = NSTextContainer(size: CGSize(width: width, height: 790 - y))
                    container.lineFragmentPadding = 0; layout.addTextContainer(container)
                    let range = layout.glyphRange(for: container)
                    layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: 44, y: y))
                    drawn = NSMaxRange(range); y += ceil(layout.usedRect(for: container).height) + 12
                    if drawn < layout.numberOfGlyphs { beginPage() }
                }
                y += 8
            }
        }
        return file
    }
}
