# macOS Orbit app — source build kit

For a ready-to-run app, [download the verified universal Mac beta](https://github.com/afilen86/PortMap/releases/download/macos-orbit-v1.5-build9/PortMap-1.5-build9.zip). The source kit below is only needed to build it yourself.

[Download the Mac build kit](https://github.com/afilen86/PortMap/raw/refs/heads/macos-orbit-app/packages/macos-orbit-app/PortMap-Mac-Build-Kit-1.5.zip)

Extract the ZIP on your Mac and double-click **Build Port Map.command**. It builds and opens **Port Map.app**, and creates a ZIP in the `build` folder. Requires macOS 14+, Xcode Command Line Tools (Swift 6), and Python 3. Alternatively run `bash build.sh --zip --run` from Terminal in the extracted folder.

This ZIP contains source and build tools, **not a compiled `.app`**. The [macOS workflow](https://github.com/afilen86/PortMap/actions/runs/43745262359) successfully compiled both architectures, verified the signature, and ran the real WebKit smoke check before publishing the app.

[Full Mac guide](../../MACOS.md) · [App source](../../port-map-source/OrbitWebView.swift)
