import Foundation

let scan = try PortScan.capture()
func output(_ nodes: [Connection], indent: String) {
    for node in nodes {
        print(indent + [node.name, node.detail, node.speed].compactMap { $0 }.joined(separator: " · "))
        output(node.children, indent: indent + "  ")
    }
}
for port in scan.ports {
    print(port.group, port.position, port.id, port.label, port.link)
    output(port.connections, indent: "  ")
}
