# SwiftyXrayKitCustom

An iOS 15+ Swift package that embeds a custom `LibXray` binary and connects
`NEPacketTunnelFlow` directly to Xray's gVisor TUN inbound through a Unix
socket pair. No local SOCKS5 or additional TUN adapter is required.

The bundled Xray build keeps `allowInsecure: true` available after the upstream
2026-06-01 removal date and exposes iOS-oriented memory and connection tuning
APIs.

## Requirements

- iOS 15 or later
- Swift 6 / Xcode 16 or later
- A Network Extension target with Packet Tunnel capability

The binary contains `ios-arm64` device and `ios-arm64_x86_64-simulator` slices.

## Installation

Add this directory as a local Swift package in Xcode and link the
`SwiftyXrayKit` product to the Packet Tunnel extension target.

## Usage

```swift
import NetworkExtension
import SwiftyXrayKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var bridge: XrayBridge?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let bridge = XrayBridge(packetFlow: packetFlow)
            try bridge.start(
                config: .json(xrayConfigJSON),
                dataDir: geoFilesDirectory,
                finalConfigPath: workingDirectory.appendingPathComponent("xray.json"),
                preset: .mobile
            )
            self.bridge = bridge
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        bridge?.stop()
        bridge = nil
        completionHandler()
    }
}
```

`XrayBridge.start` injects the TUN inbound into an intermediate Xray config.
Use `startWithRawConfig` when the configuration is already complete, or
`buildConfig` to inspect the generated dictionary without starting Xray.

`GeoFilesLoader` can download `geoip.dat` and `geosite.dat`. Applications that
need deterministic startup should download and verify those files before the
Packet Tunnel extension starts.

## Security

`allowInsecure: true` disables TLS peer-certificate validation and makes the
connection vulnerable to man-in-the-middle attacks. Use it only when explicitly
required. Certificate verification remains unchanged when the option is false.

The final Xray configuration may contain credentials. Do not forward the
`traceHandle` output to production logs unless sensitive values are redacted.

## Source provenance

| Component | Version / commit |
| --- | --- |
| Xray-core | `v26.3.27` / `d2758a023cd7f4174a5a5fa4ff66e487d4342ba0` |
| libXray Apple wrapper | `v26.3.27-ios` / `7dd886449289adc0243bf8d51b8f1e0f693f038d` |
| SwiftyXrayKit | `2.0.0` / `3c5405521ae547de110f6ea65df00b1c05f6a0bc` |
| Go toolchain | `1.26.4` |

Local modifications are recorded in
`Patches/xray-core-ios-custom.patch` and
`Patches/libxray-apple-custom.patch`.

## Rebuilding LibXray

1. Check out Xray-core at the commit above and apply the Xray patch.
2. Check out the Apple wrapper beside it and apply the wrapper patch.
3. Point the wrapper's Go module replacement to the patched Xray-core checkout.
4. Run `PATH="$HOME/go/bin:$PATH" python3 build/main.py apple gomobile`.
5. Combine the device and simulator frameworks with
   `xcodebuild -create-xcframework`, then create
   `LibXray.xcframework.zip`.

Expected archive SHA-256:

```text
376e8401e8774b4f8f6a4db8cb1a55799aff0d28e337610bf30b789542279181
```

## Licenses

See `LICENSE-SwiftyXrayKit`, `LICENSE-Xray-core`, and `LICENSE-libXray`.
