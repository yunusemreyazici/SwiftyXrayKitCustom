# SwiftyXrayKitCustom

A Swift Package designed to run Xray on iOS.
`NEPacketTunnelFlow` connects directly to Xray's gVisor TUN inbound via a Unix socket pair; no local SOCKS5 server or additional TUN adapter is required in between.

The package contains a custom compiled `LibXray.xcframework`. This build:

- Enables direct transfer of the Xray TUN file descriptor,
- Configures memory and connection limits for the Network Extension,
- Allows the use of the `allowInsecure: true` behavior, which was removed by upstream after June 1, 2026.

> [!WARNING]
> `allowInsecure: true` disables TLS certificate verification and makes the connection vulnerable to man-in-the-middle attacks. Use it only when absolutely necessary. When set to `false`, standard certificate validation proceeds unchanged.

## Requirements

- iOS 15 or later
- Swift 6 / Xcode 16 or later
- Network Extension target with Packet Tunnel capability enabled

The binary package contains the following platform slices:

- `ios-arm64`
- `ios-arm64_x86_64-simulator`

## Installation

In Xcode, navigate to **File → Add Package Dependencies → Add Local...** and select this folder. Then, link the `SwiftyXrayKit` product to your Packet Tunnel Extension target.

## Quick Start

```swift
import NetworkExtension
import SwiftyXrayKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var xrayBridge: XrayBridge?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let appGroupDirectory = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.example.vpn")!
            let dataDirectory = appGroupDirectory.appendingPathComponent("xray-data")
            let configPath = appGroupDirectory.appendingPathComponent("xray-config.json")

            let bridge = XrayBridge(packetFlow: packetFlow)
            try bridge.start(
                config: .json(xrayConfigJSON),
                dataDir: dataDirectory,
                finalConfigPath: configPath,
                preset: .mobile
            )

            xrayBridge = bridge
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        xrayBridge?.stop()
        xrayBridge = nil
        completionHandler()
    }
}
```

The `xrayConfigJSON` in the example is a valid Xray JSON string containing outbound and routing settings. `XrayBridge` automatically adds the required TUN inbound to this configuration.

## Core API

| API | Description |
| --- | --- |
| `XrayBridge.start` | Generates a configuration from a JSON string or share link, and starts Xray. |
| `XrayBridge.startWithRawConfig` | Runs the pre-prepared Xray configuration without modifying it. |
| `XrayBridge.buildConfig` | Returns the configuration that would be generated, without starting Xray. |
| `XrayBridge.stop` | Stops Xray and closes the socket pair. |
| `XrayBridge.getAndClearStats` | Returns the bytes sent/received since the last read and resets the counters. |
| `GeoFilesLoader.loadGeoFiles` | Downloads `geoip.dat` and `geosite.dat` files concurrently. |

### Using a Share Link

```swift
try bridge.start(
    config: .url("vless://..."),
    dataDir: dataDirectory,
    finalConfigPath: configPath
)
```

### Customizing Configuration

`configTransform` allows modifying the generated dictionary before it is written to the file:

```swift
try bridge.start(
    config: .json(xrayConfigJSON),
    dataDir: dataDirectory,
    finalConfigPath: configPath,
    sniffing: SniffingConfiguration(
        destOverride: ["http", "tls", "quic"],
        enabled: true,
        routeOnly: true,
        domainsExcluded: [],
        metadataOnly: false
    ),
    preset: .mobile,
    configTransform: { config in
        var config = config
        config["log"] = ["loglevel": "warning"]
        return config
    }
)
```

### Downloading Geo Files

```swift
let loader = GeoFilesLoader()

try await loader.loadGeoFiles(
    into: dataDirectory,
    geoSiteURL: nil,
    geoIPURL: nil
) { progress in
    print("Progress: \(Int(progress * 100))%")
}
```

For a stable and fast VPN startup, it is recommended to download and verify the geo files before starting the Packet Tunnel Extension.

## Tuning Profiles

The package offers two preset profiles:

- `.mobile`: Tailored for iOS Network Extension memory limits.
- `.desktop`: Uses higher connection and memory limits.

The default profile is `.mobile` on iOS and `.desktop` on macOS. A custom profile can also be created:

```swift
let preset = XrayTuningPreset(
    memoryLimitMB: 30,
    tcpBufMaxKB: 1024,
    tcpMaxInFlight: 512,
    udpMaxConns: 256,
    idleTimeoutSec: 120
)
```

## Security Notes

- Use `allowInsecure: false` in production whenever possible.
- The final Xray configuration may contain user credentials or keys.
- Since `traceHandle` can log the entire configuration, sensitive fields should be masked before using it in production logs.
- If downloaded geo files are obtained from an untrusted source, integrity verification should be performed.

## Source Versions

| Component | Version / Commit |
| --- | --- |
| Xray-core | `v26.3.27` / `d2758a023cd7f4174a5a5fa4ff66e487d4342ba0` |
| libXray Apple wrapper | `v26.3.27-ios` / `7dd886449289adc0243bf8d51b8f1e0f693f038d` |
| SwiftyXrayKit | `2.0.0` / `3c5405521ae547de110f6ea65df00b1c05f6a0bc` |
| Go | `1.26.4` |

Local modifications are stored in the following files:

- `Patches/xray-core-ios-custom.patch`
- `Patches/libxray-apple-custom.patch`

## Rebuilding LibXray

1. Checkout the Xray-core repository at the commit listed above and apply the Xray patch.
2. Checkout the Apple wrapper repository alongside it and apply the wrapper patch.
3. Redirect the wrapper's Go module replacement setting to the patched Xray-core directory.
4. Run the command `PATH="$HOME/go/bin:$PATH" python3 build/main.py apple gomobile`.
5. Combine the device and simulator frameworks using `xcodebuild -create-xcframework`.
6. Package the result as `LibXray.xcframework.zip`.

Expected SHA-256:

```text
376e8401e8774b4f8f6a4db8cb1a55799aff0d28e337610bf30b789542279181
```

## Licenses

- `LICENSE-SwiftyXrayKit`
- `LICENSE-Xray-core`
- `LICENSE-libXray`
