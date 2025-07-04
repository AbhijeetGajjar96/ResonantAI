import Foundation
import Network
import SwiftUI

class NetworkStatusViewModel: ObservableObject {
    @Published var status: NWPath.Status = .requiresConnection
    @Published var interfaceType: NWInterface.InterfaceType? = nil

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.status = path.status
                self?.interfaceType = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.first?.type
            }
        }
        monitor?.start(queue: queue)
    }

    deinit {
        monitor?.cancel()
    }
} 