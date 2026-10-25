// Pending-action approval. Approve/Cancel only call the backend; this view executes nothing.
import SwiftUI

struct ApprovalView: View {
    @ObservedObject var model: AppModel
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(request.title, systemImage: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accentColor)
            Text("In \(request.application)").font(.system(size: 14)).foregroundStyle(.secondary)
            Text(request.detail).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            if let source = request.sourcePath { pathRow("Move this file", source) }
            if let destination = request.destinationPath { pathRow("To this place", destination) }
            Text("Nothing happens until you approve. I'll check the result before telling you it worked.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelApproval() }.controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Approve") { model.approve() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.4)))
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(path).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
