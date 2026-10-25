// Shared UI contract. Owned by Codex. Claude's views use these types without reimplementing them.
import AppKit
import SwiftUI
import HowdoeyCore

struct ChatMessage: Identifiable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    let text: String
}
enum SessionPhase: String {
    case idle = "Ready", selecting = "Select an area", observing = "Looking at your selection"
    case thinking = "Thinking", awaitingApproval = "Waiting for your approval"
    case demonstrating = "Follow the highlighted step", verifying = "Checking what changed"
    case complete = "Finished", stopped = "Stopped", failed = "Needs attention"
}
enum SelectionKind { case region, element, window }
struct DemonstrationTarget {
    let rect: CGRect // Global Quartz points: origin at top left of main display. Convert once for AppKit.
    let caption: String
    var label = ""
}
struct ApprovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let application: String
    let sourcePath: String?
    let destinationPath: String?
}
struct PermissionState: Equatable {
    var accessibility = false
    var screenRecording = false
}
enum ProviderPreset: String, CaseIterable, Identifiable {
    case shared = "Howdoey shared AI", groq = "Groq", ollama = "Ollama (local)", claudeDemo = "Claude Code (cloud demo)", custom = "Custom compatible API"
    var id: String { rawValue }
}
struct ProviderConfiguration: Codable {
    var endpoint = "http://127.0.0.1:11434/v1"
    var model = "qwen3.5:2b"
    var sendImages = true
}

@MainActor final class AppModel: ObservableObject {
    @Published var mode: Mode = .show
    @Published var draft = ""
    @Published var phase: SessionPhase = .idle
    @Published var messages: [ChatMessage] = []
    @Published var selectionImage: NSImage?
    @Published var selectionDescription = "Uses your active window unless you select an area"
    @Published var targetApplication = ""
    @Published var pendingApproval: ApprovalRequest?
    @Published var demonstration: DemonstrationTarget?
    @Published var permissions = PermissionState()
    @Published var configuration = ProviderConfiguration()
    @Published var apiKeyInput = "" // In-memory input. saveSettings() writes to Keychain.
    @Published var providerPreset: ProviderPreset = .ollama
    @Published var availableModels: [String] = []
    @Published var settingsStatus = ""
    @Published var isCheckingProvider = false
    @Published var isSettingUpLocalAI = false
    @Published var localAIStatus = ""
    var localAISetupTask: Task<Void,Never>?
    @Published var selectedFileName: String?
    @Published var destinationFolderName: String?
    @Published var lastMovedFile: URL?
    @Published var stepCount = 0
    @Published var errorMessage: String?
    @Published var showSettings = false { didSet { if showSettings && isBusy { stop() } } }
    var isBusy: Bool { [.selecting, .observing, .thinking, .awaitingApproval, .demonstrating, .verifying].contains(phase) }
    var canSubmit: Bool { !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canCheckProgress: Bool { phase == .demonstrating }

    // Presentation hooks, installed exclusively by AppCoordinator. UI should invoke the public methods below instead of these hooks.
    var selectionHandler: ((SelectionKind) -> Void)?
    var demonstrationHandler: ((DemonstrationTarget?) -> Void)?
    var showPanelHandler: (() -> Void)?
    var closePanelHandler: (() -> Void)?
    let observer = Observer()
    let provider = ProviderClient()
    @Published var observation: Observation?
    var defaultTargetHandler: (() -> NSRunningApplication?)?
    var selectionIsExplicit = false
    var targetWindowID: CGWindowID?
    var targetApp: NSRunningApplication?
    var task: Task<Void, Never>?
    var progressTask: Task<Void, Never>?
    var clickCheckTask: Task<Void, Never>?
    var clickCheckPending = false
    var generation = UUID()
    var sessionMode: Mode = .show
    var conversationID = UUID()
    var sessionConversation = ""
    var sessionGoal = ""
    var sessionConfiguration = ProviderConfiguration()
    var sessionAPIKey = ""
    var history: [String] = []
    var progressExpectation: ProgressExpectation?
    var previousAction: AgentAction?
    var failureCount = 0
    var targetRefreshCount = 0
    var pendingAction: AgentAction?
    var pendingDestination: URL?
    var sourceFile: URL?
    var destinationRoot: URL?
    var sourceDigest: String?
    var lastReceipt: FileReceipt?
    var undoPending = false
    var guideFingerprint: String?
    var permissionTimer: Timer?

    init() {
        restoreSettings(); refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    // Implemented in AppModel.swift. UI entry points:
    // selectRegion(), selectElement(), selectWindow(), clearSelection(), submit(), stop(),
    // approve(), cancelApproval(), checkProgress(), chooseFile(), chooseDestination(),
    // revealMovedFile(), undoLastMove(), clearConversation(), closePanel(),
    // refreshPermissions(), requestAccessibility(), requestScreenRecording(),
    // openAccessibilitySettings(), openScreenRecordingSettings(),
    // applyProviderPreset(), saveSettings(), fetchModels(), testProvider().
}
