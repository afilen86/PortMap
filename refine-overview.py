from pathlib import Path
p=Path('work/port-map-source/SetupView.swift')
s=p.read_text()
s=s.replace('if let frame = layout.frames[device.id] {\n                            OverviewCard', 'if let frame = layout.frames[device.id], !(items.hasStack && (device.id == "host" || device.art == .satechi)) {\n                            OverviewCard',1)
s=s.replace('''                    }
                }
                .frame(width: layout.size.width''','''                    }
                    if items.hasStack, let host = items.devices.first(where: { $0.id == "host" }),
                       let stand = items.devices.first(where: { $0.art == .satechi }) {
                        OverviewStack(host: host, stand: stand, selectedID: selectedID) { selectedID = $0 }
                            .frame(width: 280, height: 240)
                            .position(x: 600, y: 558)
                    }
                }
                .frame(width: layout.size.width''',1)
s=s.replace('''    var interfaces: [OverviewInterface] = []

    init(scan''','''    var interfaces: [OverviewInterface] = []
    var hasStack: Bool { devices.contains { $0.art == .satechi } }

    init(scan''',1)
s += '''

private struct OverviewStack: View {
    let host: OverviewDevice
    let stand: OverviewDevice
    let selectedID: String?
    let select: (String) -> Void
    @State private var inspectHost = false
    @State private var inspectStand = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                select(host.id)
                inspectHost = true
            } label: {
                Text(host.title).font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.top, 11).padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $inspectHost) { OverviewInspector(device: host) }
            GeometryReader { geometry in
                ZStack {
                    if let image = DeviceArt.satechi.image {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 210, height: 140).offset(y: 31)
                    }
                    if let image = DeviceArt.macMini.image {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 200, height: 150).offset(y: -20)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture { select(host.id); inspectHost = true }
                .accessibilityLabel("Mac mini sitting on Satechi Stand & Hub")
            }
            Button {
                select(stand.id)
                inspectStand = true
            } label: {
                VStack(spacing: 2) {
                    Text(stand.title).font(.system(size: 13, weight: .semibold))
                    Text(stand.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 4).padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Inspect Satechi Stand & Hub")
            .popover(isPresented: $inspectStand) { OverviewInspector(device: stand) }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(selectedID == host.id || selectedID == stand.id ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
'''
p.write_text(s)
