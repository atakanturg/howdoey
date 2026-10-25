import Foundation
import AVFoundation

guard CommandLine.arguments.count == 3 else { fatalError("Usage: swift export-demo-video.swift input.mov output.mp4") }
let input = URL(fileURLWithPath:CommandLine.arguments[1])
let output = URL(fileURLWithPath:CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath:output.path) else { fatalError("Output already exists; choose a new filename") }
let asset = AVURLAsset(url:input)
guard let export = AVAssetExportSession(asset:asset,presetName:AVAssetExportPreset1920x1080) else { fatalError("Could not create video export") }
export.outputURL = output; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
export.exportAsynchronously {
    if export.status == .completed { print("Exported browser-ready MP4: \(output.lastPathComponent)"); exit(0) }
    fputs("Export failed: \(export.error?.localizedDescription ?? "Unknown error")\n",stderr); exit(1)
}
dispatchMain()
