import Foundation

public enum TransferOutcome: Equatable, Sendable {
    case copied, alreadyExists, targetNotSignedIn, failed(String)
}

public enum TransferError: Error, Equatable {
    case targetNotLoggedIn
}

/// Copies Code-session metadata files into another data dir. Transcripts live in ~/.claude
/// and are shared by every profile, so the metadata file is all that needs to move.
public enum SessionTransfer {
    public static func transfer(_ sessions: [SessionInfo], to target: ClaudeDataDir,
                                targetOrg: String?) throws -> [String: TransferOutcome] {
        guard let destDir = target.sessionsDir(org: targetOrg) else { throw TransferError.targetNotLoggedIn }
        let fm = FileManager.default
        var result: [String: TransferOutcome] = [:]
        for session in sessions {
            let dest = destDir.appendingPathComponent(session.fileURL.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                result[session.id] = .alreadyExists
                continue
            }
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                try Data(contentsOf: session.fileURL).write(to: dest, options: .atomic)
                result[session.id] = .copied
            } catch {
                Log.error("Transfer of session \(session.id) failed: \(error.localizedDescription)")
                result[session.id] = .failed(error.localizedDescription)
            }
        }
        return result
    }
}
