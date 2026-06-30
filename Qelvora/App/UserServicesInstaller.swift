import Foundation

enum UserServicesInstaller {
    struct Diagnostic: Equatable {
        let servicesDirectoryPath: String
        let workflowPath: String
        let workflowExists: Bool
        let infoPlistIsValid: Bool
        let documentWorkflowExists: Bool
        let lastModified: Date?

        var isHealthy: Bool {
            workflowExists && infoPlistIsValid && documentWorkflowExists
        }
    }

    struct InstallReport: Equatable {
        let diagnostic: Diagnostic
        let registrationSucceeded: Bool
        let pasteboardFlushSucceeded: Bool
        let pasteboardUpdateSucceeded: Bool
        let errorDescription: String?

        var isComplete: Bool {
            diagnostic.isHealthy
                && registrationSucceeded
                && pasteboardFlushSucceeded
                && pasteboardUpdateSucceeded
                && errorDescription == nil
        }

        var summary: String {
            if let errorDescription {
                return "Installation incomplete: \(errorDescription)"
            }

            if isComplete {
                return "Service reinstalled. Quit and reopen the target app if macOS does not refresh the menu."
            }

            return "Service written, but macOS did not confirm the full refresh. Restart the target app."
        }
    }

    private static let workflowName = "Correct with Qelvora.workflow"
    private static let legacyWorkflowName = "Corriger avec Qelvora.workflow"
    private static let serviceDisplayName = "Correct with Qelvora"
    private static let serviceBundleIdentifier = "io.qelvora.Qelvora.CorrectService"
    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let pasteboardServerPath = "/System/Library/CoreServices/pbs"

    static func installOrRefresh(fileManager: FileManager = .default) -> InstallReport {
        guard let servicesURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Services", isDirectory: true) else {
            let diagnostic = Diagnostic(
                servicesDirectoryPath: "Unavailable",
                workflowPath: "Unavailable",
                workflowExists: false,
                infoPlistIsValid: false,
                documentWorkflowExists: false,
                lastModified: nil
            )
            return InstallReport(
                diagnostic: diagnostic,
                registrationSucceeded: false,
                pasteboardFlushSucceeded: false,
                pasteboardUpdateSucceeded: false,
                errorDescription: "Unable to locate ~/Library/Services."
            )
        }

        let workflowURL = servicesURL.appendingPathComponent(workflowName, isDirectory: true)
        let legacyWorkflowURL = servicesURL.appendingPathComponent(legacyWorkflowName, isDirectory: true)
        let contentsURL = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        do {
            if workflowName != legacyWorkflowName,
               fileManager.fileExists(atPath: legacyWorkflowURL.path) {
                try? fileManager.removeItem(at: legacyWorkflowURL)
            }

            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
            try writePlist(infoPlist(), to: contentsURL.appendingPathComponent("Info.plist"))
            try writePlist(documentWorkflow(), to: resourcesURL.appendingPathComponent("document.wflow"))
            try writePlist(versionPlist(), to: contentsURL.appendingPathComponent("version.plist"))
        } catch {
            return InstallReport(
                diagnostic: diagnostics(fileManager: fileManager),
                registrationSucceeded: false,
                pasteboardFlushSucceeded: false,
                pasteboardUpdateSucceeded: false,
                errorDescription: error.localizedDescription
            )
        }

        let registrationSucceeded = run(lsregisterPath, arguments: ["-f", workflowURL.path])
        let pasteboardFlushSucceeded = run(pasteboardServerPath, arguments: ["-flush"])
        let pasteboardUpdateSucceeded = run(pasteboardServerPath, arguments: ["-update"])

        return InstallReport(
            diagnostic: diagnostics(fileManager: fileManager),
            registrationSucceeded: registrationSucceeded,
            pasteboardFlushSucceeded: pasteboardFlushSucceeded,
            pasteboardUpdateSucceeded: pasteboardUpdateSucceeded,
            errorDescription: nil
        )
    }

    static func diagnostics(fileManager: FileManager = .default) -> Diagnostic {
        guard let servicesURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Services", isDirectory: true) else {
            return Diagnostic(
                servicesDirectoryPath: "Unavailable",
                workflowPath: "Unavailable",
                workflowExists: false,
                infoPlistIsValid: false,
                documentWorkflowExists: false,
                lastModified: nil
            )
        }

        let workflowURL = servicesURL.appendingPathComponent(workflowName, isDirectory: true)
        let contentsURL = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let documentWorkflowURL = resourcesURL.appendingPathComponent("document.wflow")
        let attributes = try? fileManager.attributesOfItem(atPath: workflowURL.path)

        return Diagnostic(
            servicesDirectoryPath: servicesURL.path,
            workflowPath: workflowURL.path,
            workflowExists: fileManager.fileExists(atPath: workflowURL.path),
            infoPlistIsValid: isValidInfoPlist(at: infoPlistURL),
            documentWorkflowExists: fileManager.fileExists(atPath: documentWorkflowURL.path),
            lastModified: attributes?[.modificationDate] as? Date
        )
    }

    static func infoPlist() -> [String: Any] {
        [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": serviceBundleIdentifier,
            "CFBundleName": serviceDisplayName,
            "CFBundleShortVersionString": "1.0",
            "NSServices": [
                [
                    "NSMenuItem": [
                        "default": serviceDisplayName
                    ],
                    "NSMessage": "runWorkflowAsService",
                    "NSSendTypes": [
                        "public.utf8-plain-text"
                    ]
                ]
            ]
        ]
    }

    static func documentWorkflow() -> [String: Any] {
        let command = """
        tmp="${TMPDIR:-/tmp}/qelvora-service-$(/usr/bin/uuidgen).txt"
        /bin/cat > "$tmp"
        /usr/bin/open "qelvora://correct-file?path=$tmp"
        """

        return [
            "actions": [
                [
                    "action": [
                        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                        "ActionName": "Run Shell Script",
                        "ActionParameters": [
                            "CheckedForUserDefaultShell": true,
                            "COMMAND_STRING": command,
                            "inputMethod": 0,
                            "shell": "/bin/bash",
                            "source": ""
                        ],
                        "AMAccepts": [
                            "Container": "List",
                            "Optional": true,
                            "Types": [
                                "com.apple.cocoa.string"
                            ]
                        ],
                        "AMActionVersion": "2.0.3",
                        "AMApplication": [
                            "Automator"
                        ],
                        "AMParameterProperties": [
                            "CheckedForUserDefaultShell": [:],
                            "COMMAND_STRING": [:],
                            "inputMethod": [:],
                            "shell": [:],
                            "source": [:]
                        ],
                        "AMProvides": [
                            "Container": "List",
                            "Types": [
                                "com.apple.cocoa.string"
                            ]
                        ],
                        "arguments": [
                            "0": [
                                "default value": 0,
                                "name": "inputMethod",
                                "required": "0",
                                "type": "0",
                                "uuid": "0"
                            ],
                            "1": [
                                "default value": "",
                                "name": "source",
                                "required": "0",
                                "type": "0",
                                "uuid": "1"
                            ],
                            "2": [
                                "default value": false,
                                "name": "CheckedForUserDefaultShell",
                                "required": "0",
                                "type": "0",
                                "uuid": "2"
                            ],
                            "3": [
                                "default value": "",
                                "name": "COMMAND_STRING",
                                "required": "0",
                                "type": "0",
                                "uuid": "3"
                            ],
                            "4": [
                                "default value": "/bin/sh",
                                "name": "shell",
                                "required": "0",
                                "type": "0",
                                "uuid": "4"
                            ]
                        ],
                        "BundleIdentifier": "com.apple.RunShellScript",
                        "CanShowSelectedItemsWhenRun": false,
                        "CanShowWhenRun": true,
                        "Category": [
                            "AMCategoryUtilities"
                        ],
                        "CFBundleVersion": "2.0.3",
                        "Class Name": "RunShellScriptAction",
                        "InputUUID": "3999E39F-84D7-4F76-B2FD-4B25F2B35924",
                        "isViewVisible": true,
                        "Keywords": [
                            "Shell",
                            "Script",
                            "Command",
                            "Run",
                            "Unix"
                        ],
                        "location": "309.500000:631.000000",
                        "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/en.lproj/main.nib",
                        "OutputUUID": "65A65392-8710-4E5A-960C-1150629E03F5",
                        "UnlocalizedApplications": [
                            "Automator"
                        ],
                        "UUID": "0D124779-7706-4B34-8D51-D155FA2B0D6D"
                    ],
                    "isViewVisible": true
                ]
            ],
            "AMApplicationBuild": "346",
            "AMApplicationVersion": "2.3",
            "AMDocumentVersion": "2",
            "connectors": [:],
            "state": [
                "workflowViewScrollPosition": "{{0, 0}, {741, 617}}"
            ],
            "workflowMetaData": [
                "serviceApplicationBundleID": "",
                "serviceApplicationPath": "",
                "serviceInputTypeIdentifier": "com.apple.Automator.text",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 1,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ]
        ]
    }

    private static func versionPlist() -> [String: Any] {
        [
            "BuildVersion": "1",
            "ProjectName": "Qelvora Service",
            "SourceVersion": "1",
            "CFBundleShortVersionString": "1.0"
        ]
    }

    private static func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        if let existingData = try? Data(contentsOf: url),
           existingData == data {
            return
        }

        try data.write(to: url, options: .atomic)
    }

    private static func isValidInfoPlist(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              let services = plist["NSServices"] as? [[String: Any]],
              let firstService = services.first else {
            return false
        }

        return plist["CFBundleIdentifier"] as? String == serviceBundleIdentifier
            && plist["CFBundleName"] as? String == serviceDisplayName
            && firstService["NSMessage"] as? String == "runWorkflowAsService"
            && firstService["NSSendTypes"] as? [String] == ["public.utf8-plain-text"]
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
