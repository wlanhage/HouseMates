import SwiftUI
import UniformTypeIdentifiers

/// Delningstillägget i Safari: lägger receptlänken i appens inkorg (`RecipeInbox`) och
/// berättar att receptet hämtas när appen öppnas.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            let link = await sharedLink()
            if let link { RecipeInbox.add(link) }
            show(SharedLinkView(saved: link != nil) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
        }
    }

    private func sharedLink() async -> String? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               ["http", "https"].contains(url.scheme) {
                return url.absoluteString
            }
        }
        return nil
    }

    private func show(_ content: some View) {
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct SharedLinkView: View {
    let saved: Bool
    let done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: saved ? "fork.knife" : "link.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(saved ? "Sparas i Våra middagar" : "Hittade ingen länk")
                    .font(.headline)
                Text(saved
                    ? "Receptet hämtas nästa gång du öppnar HouseMates."
                    : "Dela en receptsida från Safari för att spara den.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klart", action: done)
                }
            }
        }
    }
}
