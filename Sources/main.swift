import Foundation
import IOKit.pwr_mgt

// MARK: - IOKit Message Constants (C macros unavailable in Swift)
// iokit_common_msg(x) = (0xE0000000 | x)

let kIOMsgSystemHasPoweredOn: UInt32 = 0xE0000300
let kIOMsgCanSystemSleep: UInt32     = 0xE0000270
let kIOMsgSystemWillSleep: UInt32    = 0xE0000280

let nullAssertion = IOPMAssertionID(kIOPMNullAssertionID)

// MARK: - Configuration
// version is defined in Sources/Version.swift (generated at build time)

func parseArguments() -> TimeInterval {
    let args = CommandLine.arguments
    for (i, arg) in args.enumerated() {
        if (arg == "-t" || arg == "--time"), i + 1 < args.count,
           let seconds = TimeInterval(args[i + 1]), seconds > 0 {
            return seconds
        }
    }
    if args.contains("-h") || args.contains("--help") {
        print("""
        osx-clamshell-guard v\(version)
        Prevents clamshell sleep during USB-C dock power delivery renegotiation.

        Usage: osx-clamshell-guard [-t <seconds>]

        Options:
          -t, --time <seconds>   Grace period after wake (default: 30)
          -h, --help             Show this help
          -V, --version          Show version
        """)
        exit(0)
    }
    if args.contains("-V") || args.contains("--version") {
        print("osx-clamshell-guard v\(version)")
        exit(0)
    }
    return 30.0
}

let gracePeriod = parseArguments()

// MARK: - State

var rootPort: io_connect_t = 0
var notificationPort: IONotificationPortRef?
var notifier: io_object_t = 0
var currentAssertionID: IOPMAssertionID = nullAssertion
var graceTimer: DispatchSourceTimer?

var inGracePeriod: Bool {
    currentAssertionID != nullAssertion
}

// MARK: - Logging

let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ message: String) {
    let ts = logFormatter.string(from: Date())
    print("[\(ts)] \(message)")
    fflush(stdout)
}

// MARK: - Grace Period Management

func startGracePeriod() {
    // Cancel any existing grace period
    graceTimer?.cancel()
    graceTimer = nil

    // Release any existing assertion before creating a new one
    if inGracePeriod {
        IOPMAssertionRelease(currentAssertionID)
        currentAssertionID = nullAssertion
    }

    let reason = "osx-clamshell-guard: dock PD renegotiation grace period" as CFString
    var assertionID = nullAssertion
    let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason,
        &assertionID
    )

    if result == kIOReturnSuccess {
        currentAssertionID = assertionID
        log("Wake detected — preventing sleep for \(Int(gracePeriod))s")
    } else {
        log("Warning: failed to create sleep assertion (IOReturn: \(result))")
        return
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + gracePeriod)
    timer.setEventHandler {
        endGracePeriod()
    }
    timer.resume()
    graceTimer = timer
}

func endGracePeriod() {
    graceTimer?.cancel()
    graceTimer = nil

    if inGracePeriod {
        IOPMAssertionRelease(currentAssertionID)
        currentAssertionID = nullAssertion
        log("Grace period ended — normal sleep behavior restored")
    }
}

// MARK: - IOKit Power Callback

let powerCallback: IOServiceInterestCallback = {
    refCon, service, messageType, messageArgument in

    switch messageType {
    case kIOMsgSystemHasPoweredOn:
        startGracePeriod()

    case kIOMsgCanSystemSleep:
        if inGracePeriod {
            // Deny the sleep request during the grace period
            IOCancelPowerChange(rootPort, Int(bitPattern: messageArgument))
            log("Denied sleep request during grace period")
        } else {
            IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        }

    case kIOMsgSystemWillSleep:
        // Must always acknowledge forced sleep (e.g. user-initiated, low battery)
        IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        log("System going to sleep")

    default:
        break
    }
}

// MARK: - Signal Handling (via GCD for async-signal-safety)

var signalSources: [DispatchSourceSignal] = []

func setupSignalHandlers() {
    // Ignore at POSIX level so DispatchSource handles delivery
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)

    for sig: Int32 in [SIGTERM, SIGINT] {
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            endGracePeriod()
            log("Received signal \(sig) — shutting down")
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

// MARK: - Main

setupSignalHandlers()

rootPort = IORegisterForSystemPower(nil, &notificationPort, powerCallback, &notifier)
guard rootPort != 0 else {
    log("Error: failed to register for system power notifications")
    exit(1)
}

guard let port = notificationPort else {
    log("Error: notification port is nil")
    exit(1)
}

CFRunLoopAddSource(
    CFRunLoopGetCurrent(),
    IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
    .defaultMode
)

log("osx-clamshell-guard v\(version) started (grace period: \(Int(gracePeriod))s)")
CFRunLoopRun()
