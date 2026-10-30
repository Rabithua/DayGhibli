import Foundation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    var needsApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    func openSettings()
}

@MainActor
struct LoginItemController: LoginItemManaging {
    private let service = SMAppService.mainApp

    // Pending approval still represents a registered request, not permission to run.
    var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval: true
        case .notRegistered, .notFound: false
        @unknown default: false
        }
    }

    var needsApproval: Bool {
        service.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        switch service.status {
        case .enabled, .requiresApproval:
            if !enabled { try service.unregister() }
        case .notRegistered:
            if enabled { try service.register() }
        case .notFound:
            throw LoginItemError.serviceNotFound
        @unknown default:
            throw LoginItemError.unknownStatus
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private enum LoginItemError: LocalizedError {
    case serviceNotFound
    case unknownStatus

    var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            "系统未找到应用的登录启动项，请确认应用完整后重新打开。"
        case .unknownStatus:
            "暂时无法读取登录启动状态，请稍后重试。"
        }
    }
}
