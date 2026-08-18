import Foundation

public enum HarnessSeatbeltProfile {
    public static func make(taskRoot: URL) -> String {
        let root = escape(taskRoot.standardizedFileURL.resolvingSymlinksInPath().path)
        return """
        (version 1)
        (deny default)

        (allow process-exec)
        (allow process-fork)
        (allow process-info* (target same-sandbox))
        (allow signal (target same-sandbox))
        (allow mach-priv-task-port (target same-sandbox))

        (allow user-preference-read)
        (allow ipc-posix-shm)
        (allow ipc-posix-sem)
        (allow sysctl-read)
        (allow iokit-get-properties)
        (allow system-socket (require-all (socket-domain AF_SYSTEM) (socket-protocol 2)))

        (allow mach-lookup
          (global-name "com.apple.bsd.dirhelper")
          (global-name "com.apple.FontObjectsServer")
          (global-name "com.apple.fonts")
          (global-name "com.apple.logd")
          (global-name "com.apple.SecurityServer")
          (global-name "com.apple.securityd.xpc")
          (global-name "com.apple.system.logger")
          (global-name "com.apple.system.opendirectoryd.libinfo")
          (global-name "com.apple.system.opendirectoryd.membership"))

        (allow file-read-metadata (vnode-type DIRECTORY))
        (allow file-read* (literal "/"))
        (allow file-read* (subpath "/System"))
        (allow file-read* (subpath "/usr"))
        (allow file-read* (subpath "/bin"))
        (allow file-read* (subpath "/sbin"))
        (allow file-read* (subpath "/Library/Developer"))
        (allow file-read* (subpath "/Library/Frameworks"))
        (allow file-read* (subpath "/Library/Apple"))
        (allow file-read* (subpath "/Applications/Xcode.app"))
        (allow file-read* (subpath "/Applications/Xcode-beta.app"))
        (allow file-read* (subpath "/private/etc"))
        (allow file-read* (subpath "/private/var/db/dyld"))
        (allow file-read* (subpath "/private/var/db/timezone"))
        (allow file-read* (subpath "/private/var/select"))
        (allow file-read* (subpath "/dev"))
        (allow file-read* (subpath "\(root)"))
        (allow file-write* (subpath "\(root)"))

        (allow file-ioctl
          (literal "/dev/null")
          (literal "/dev/zero")
          (literal "/dev/random")
          (literal "/dev/urandom"))
        (allow file-read-data file-write-data
          (literal "/dev/null")
          (literal "/dev/zero")
          (literal "/dev/random")
          (literal "/dev/urandom"))
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
