import Foundation

/// "Yalnızca Sistem Sesi Kaydı" izninin durumu ve istenmesi.
/// macOS bunun için genel bir API sunmuyor; TCC çerçevesindeki fonksiyonları çalışma anında
/// çağırıyoruz (Apple'ın AudioCap örneğinde kullanılan yöntem). Bulunamazsa .unknown döner.
enum AudioPermission {
    enum Status { case notDetermined, denied, authorized, unknown }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) @escaping (Bool) -> Void) -> Void

    static var status: Status {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        case 2: return .notDetermined
        default: return .unknown
        }
    }

    /// macOS'un izin penceresini gösterir.
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else {
            Task { @MainActor in completion(false) }
            return
        }
        unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    static func openSystemSettings() {
        NSWorkspaceOpen("x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }
}

import AppKit

private func NSWorkspaceOpen(_ string: String) {
    if let url = URL(string: string) { NSWorkspace.shared.open(url) }
}
