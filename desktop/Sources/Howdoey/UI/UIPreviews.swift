// Preview-only fixtures. Never referenced by the running app.
import SwiftUI

#if DEBUG
struct ChatPanelPreview: PreviewProvider {
    static var previews: some View {
        let model = AppModel()
        model.targetApplication = "System Settings"
        model.messages = [ChatMessage(role: .user, text: "What does this do?"), ChatMessage(role: .assistant, text: "PREVIEW ONLY sample text.")]
        return ChatPanelView(model: model).frame(width: 420, height: 680)
    }
}
struct ApprovalPreview: PreviewProvider {
    static var previews: some View {
        ApprovalView(model: AppModel(), request: ApprovalRequest(title: "Move a file", detail: "PREVIEW ONLY", application: "Finder", sourcePath: "/Users/me/Downloads/a.pdf", destinationPath: "/Users/me/Documents/Taxes/a.pdf"))
            .padding().frame(width: 420)
    }
}
#endif
