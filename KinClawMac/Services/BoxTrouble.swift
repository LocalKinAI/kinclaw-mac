import Foundation

/// Whether a failed call to the box says anything about the job behind it.
///
/// A connection refused, a timeout, a dropped connection, ssh's own exit 255, curl's "could not get
/// through" codes — those are the road, not the job: a job on the box may well be running on. Only
/// the backend's own word fails a job (ComfyUI's error or interruption, Pixelle's "failed", a
/// program's nonzero exit). The agents' notebooks kept finding the opposite: a 20-second curl
/// timeout read as a failed Pixelle film that ran on for an hour (2026-10-10), a lost /view fetch
/// throwing away a finished shot.
enum BoxTrouble {
    static func isTransient(_ error: Error) -> Bool {
        if let job = error as? ComfyJob.Trouble, case .unreachable = job { return true }
        if let url = error as? URLError {
            return [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
                    .timedOut, .dnsLookupFailed, .badServerResponse, .resourceUnavailable,
                    .secureConnectionFailed, .cannotLoadFromNetwork].contains(url.code)
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain,
           [ECONNREFUSED, ECONNRESET, ETIMEDOUT, EHOSTUNREACH, ENETUNREACH, ENETDOWN, EHOSTDOWN, EPIPE].contains(Int32(ns.code)) {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return ["could not connect", "连不上", "connection refused", "network connection was lost", "timed out",
                "offline", "connection reset", "no route to host"].contains { text.contains($0) }
    }

    /// ssh and curl by exit code: ssh's 255 is ssh not getting there; curl's 5, 6, 7, 28, 35, 52, 55
    /// and 56 are its road (resolve, connect, time out, TLS, empty reply, send, receive).
    static func isTransient(exit code: Int32) -> Bool {
        [5, 6, 7, 28, 35, 52, 55, 56, 255].contains(code)
    }
}
