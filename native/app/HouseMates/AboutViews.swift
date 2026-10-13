import SwiftUI

struct AboutSection: View {
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        Section {
            NavigationLink("Integritetspolicy") { PolicyView() }
            if let supportEmail, let url = URL(string: "mailto:\(supportEmail)") {
                Link("Kontakta oss", destination: url)
            }
            LabeledContent("Version", value: "\(info["CFBundleShortVersionString"] ?? "") (\(info["CFBundleVersion"] ?? ""))")
        } header: {
            SectionTitle("Om HouseMates")
        }
    }

    /// Från Config/*.xcconfig (SUPPORT_EMAIL); raden visas inte förrän adressen är ifylld.
    private var supportEmail: String? {
        (info["SupportEmail"] as? String).flatMap { $0.contains("@") ? $0 : nil }
    }
}

/// Visar integritetspolicyn.md, samma text som publiceras på webben för App Store.
struct PolicyView: View {
    private let blocks = MarkdownBlock.parse(
        Bundle.main.url(forResource: "integritetspolicy", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    switch block.kind {
                    case .title: Text(block.text).font(.title2.bold())
                    case .heading: Text(block.text).font(.headline).padding(.top, 8)
                    case .bullet: Text("•  ") + Text(markdown(block.text))
                    case .paragraph: Text(markdown(block.text))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Integritetspolicy")
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// Det lilla av Markdown som policyn använder: rubriker, punktlistor och stycken.
struct MarkdownBlock: Identifiable, Equatable {
    enum Kind { case title, heading, bullet, paragraph }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func add(_ kind: Kind, _ text: String) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text))
        }
        func endParagraph() {
            if !paragraph.isEmpty { add(.paragraph, paragraph.joined(separator: " ")) }
            paragraph = []
        }
        for line in markdown.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("# ") {
                endParagraph()
                add(.title, String(line.dropFirst(2)))
            } else if line.hasPrefix("## ") {
                endParagraph()
                add(.heading, String(line.dropFirst(3)))
            } else if line.hasPrefix("- ") {
                endParagraph()
                add(.bullet, String(line.dropFirst(2)))
            } else if line.isEmpty {
                endParagraph()
            } else {
                paragraph.append(line)
            }
        }
        endParagraph()
        return blocks
    }
}
