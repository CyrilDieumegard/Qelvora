import AppKit
import CoreServices
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = QelvoraServiceProvider()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var didRegisterServicesProvider = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerURLHandler()
        registerUpdateHandler()
        prepareServicesRegistration()
        _ = UserServicesInstaller.installOrRefresh()
    }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        NotificationCenter.default.post(name: .qelvoraOpenURL, object: url)
    }

    private func registerUpdateHandler() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUpdates(_:)),
            name: .qelvoraCheckForUpdates,
            object: nil
        )
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    private func prepareServicesRegistration() {
        let bundleURL = Bundle.main.bundleURL
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let defaultsKey = "lastServiceRegistrationRepairBuild"

        guard UserDefaults.standard.string(forKey: defaultsKey) != bundleVersion else {
            registerServicesProviderIfNeeded()
            return
        }

        DispatchQueue.global(qos: .utility).async {
            ServiceRegistrationRepair.repair(currentBundleURL: bundleURL)

            DispatchQueue.main.async { [weak self] in
                UserDefaults.standard.set(bundleVersion, forKey: defaultsKey)
                self?.registerServicesProviderIfNeeded()
            }
        }
    }

    private func registerServicesProviderIfNeeded() {
        guard !didRegisterServicesProvider else {
            NSUpdateDynamicServices()
            return
        }

        let bundleURL = Bundle.main.bundleURL

        _ = LSRegisterURL(bundleURL as CFURL, true)
        NSApp.servicesProvider = serviceProvider
        NSUnregisterServicesProvider("Qelvora")
        NSRegisterServicesProvider(serviceProvider, "Qelvora")
        NSUpdateDynamicServices()
        didRegisterServicesProvider = true
    }
}

enum ServiceRegistrationRepair {
    private static let bundleIdentifier = "io.qelvora.Qelvora"
    private static let appName = "Qelvora.app"
    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let pasteboardServerPath = "/System/Library/CoreServices/pbs"

    static func repair(currentBundleURL: URL, fileManager: FileManager = .default) {
        for staleURL in staleBundleURLs(currentBundleURL: currentBundleURL, fileManager: fileManager) {
            run(lsregisterPath, arguments: ["-u", staleURL.path])
        }

        run(lsregisterPath, arguments: ["-f", currentBundleURL.path])
        run(pasteboardServerPath, arguments: ["-flush"])
        run(pasteboardServerPath, arguments: ["-update"])
    }

    static func staleBundleURLs(currentBundleURL: URL, fileManager: FileManager = .default) -> [URL] {
        let currentPath = currentBundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        var candidates: [URL] = []

        candidates.append(contentsOf: mountedQelvoraBundleURLs(fileManager: fileManager))

        [
            "/private/tmp/qelvora-derived/Build/Products/Debug/\(appName)",
            "/tmp/qelvora-derived/Build/Products/Debug/\(appName)",
            "/tmp/QelvoraDerivedData/Build/Products/Debug/\(appName)",
            "/tmp/qelvora-dmg-derived/Build/Products/Release/\(appName)"
        ].forEach { path in
            candidates.append(URL(fileURLWithPath: path))
        }

        var seen = Set<String>()

        return candidates.compactMap { candidateURL in
            let standardizedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
            let path = standardizedURL.path

            guard path != currentPath,
                  seen.insert(path).inserted,
                  isQelvoraBundle(at: standardizedURL, fileManager: fileManager) else {
                return nil
            }

            return standardizedURL
        }
    }

    private static func mountedQelvoraBundleURLs(fileManager: FileManager) -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)

        guard let volumeURLs = try? fileManager.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return volumeURLs.map { volumeURL in
            volumeURL.appendingPathComponent(appName, isDirectory: true)
        }
    }

    private static func isQelvoraBundle(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == bundleIdentifier else {
            return false
        }

        return true
    }

    @discardableResult
    private static func run(_ launchPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
