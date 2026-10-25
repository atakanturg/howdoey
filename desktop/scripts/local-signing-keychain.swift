// Private, dedicated local build keychain. No certificate trust settings are changed.
import Foundation
import Security

func check(_ status: OSStatus, _ operation: String) {
    guard status == errSecSuccess else {
        fputs("\(operation) failed (\(status)): \(SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Security error")\n", stderr)
        exit(1)
    }
}
let args = CommandLine.arguments
let directory = URL(fileURLWithPath: args[2], isDirectory: true)
let password = try Data(contentsOf: directory.appendingPathComponent("keychain-password"))
let keychainPath = directory.appendingPathComponent("Howdoey Development.keychain").path
var keychain: SecKeychain?
if FileManager.default.fileExists(atPath: directory.appendingPathComponent("keychain-path").path) {
    let path = try String(contentsOf: directory.appendingPathComponent("keychain-path"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    check(SecKeychainOpen(path, &keychain), "Open development keychain")
} else {
    password.withUnsafeBytes { bytes in
        check(SecKeychainCreate(keychainPath, UInt32(password.count), bytes.baseAddress, false, nil, &keychain), "Create development keychain")
    }
    var size: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(size))
    check(SecKeychainGetPath(keychain!, &size, &buffer), "Find development keychain")
    try String(cString: buffer).write(to: directory.appendingPathComponent("keychain-path"), atomically: true, encoding: .utf8)
}
password.withUnsafeBytes { check(SecKeychainUnlock(keychain!, UInt32(password.count), $0.baseAddress, true), "Unlock development keychain") }
if args[1] == "import" {
    var trusted: SecTrustedApplication?
    check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &trusted), "Restrict signing key access")
    var access: SecAccess?
    check(SecAccessCreate("Howdoey Local Development Signing" as CFString, [trusted!] as CFArray, &access), "Create signing ACL")
    let p12 = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let phrase = String(data: password, encoding: .utf8)!
    let options: [String: Any] = [
        kSecImportExportPassphrase as String: phrase,
        kSecImportExportKeychain as String: keychain!,
        kSecImportExportAccess as String: access!
    ]
    var result: CFArray?
    check(SecPKCS12Import(p12 as CFData, options as CFDictionary, &result), "Import development identity")
}

if args[1] == "trust-for-codesign" {
    // Explicit user authorization is required before invoking this mode.
    let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                              kSecMatchSearchList as String: [keychain!],
                              kSecReturnRef as String: true,
                              kSecMatchLimit as String: kSecMatchLimitOne]
    var result: CFTypeRef?
    check(SecItemCopyMatching(query as CFDictionary, &result), "Find local signing certificate")
    let certificate = result as! SecCertificate
    var codesign: SecTrustedApplication?
    check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &codesign), "Limit trust to codesign")
    let rule: [String: Any] = [
        kSecTrustSettingsPolicy as String: SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil)!,
        kSecTrustSettingsApplication as String: codesign!,
        kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
    ]
    check(SecTrustSettingsSetTrustSettings(certificate, .user, [rule] as CFArray), "Set user-level code-signing trust")
    var searchList: CFArray?
    check(SecKeychainCopySearchList(&searchList), "Read keychain search list")
    var keychains = searchList as? [SecKeychain] ?? []
    if !keychains.contains(where: { CFEqual($0, keychain!) }) {
        keychains.append(keychain!)
        check(SecKeychainSetSearchList(keychains as CFArray), "Add development keychain for certificate chain lookup")
    }
    print("User-level trust restricted to code signing by /usr/bin/codesign was configured.")
}
