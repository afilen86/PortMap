# macOS Orbit app — source build kit

[Download the Mac build kit](https://github.com/afilen86/PortMap/raw/refs/heads/macos-orbit-app/packages/macos-orbit-app/PortMap-Mac-Build-Kit-1.5.zip)

Extract the ZIP on your Mac and double-click **Build Port Map.command**. It builds and opens **Port Map.app**, and creates a ZIP in the `build` folder. Requires macOS 14+, Xcode Command Line Tools (Swift 6), and Python 3. Alternatively run `bash build.sh --zip --run` from Terminal in the extracted folder.

This ZIP contains source and build tools, **not a compiled `.app`**. The Linux workspace can validate the web bridge but cannot compile AppKit/WebKit. The [macOS workflow](https://github.com/afilen86/PortMap/actions/workflows/macos-app.yml) is configured to compile, run the real WebKit smoke check, and upload the built app when a Mac runner executes it.

[Full Mac guide](../../MACOS.md) · [App source](../../port-map-source/OrbitWebView.swift)
