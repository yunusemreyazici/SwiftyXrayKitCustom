# SwiftyXrayKitCustom

iOS üzerinde Xray çalıştırmak için hazırlanmış Swift Package paketidir.
`NEPacketTunnelFlow`, Unix socket pair üzerinden doğrudan Xray’in gVisor TUN
inbound’una bağlanır; arada yerel SOCKS5 sunucusu veya ek bir TUN adaptörü
gerekmez.

Paket, özel derlenmiş bir `LibXray.xcframework` içerir. Bu derleme:

- Xray TUN dosya tanıtıcısının doğrudan aktarılmasını,
- Network Extension için bellek ve bağlantı limitlerinin ayarlanmasını,
- upstream tarafından 1 Haziran 2026 sonrasında kaldırılan
  `allowInsecure: true` davranışının kullanılmasını sağlar.

> [!WARNING]
> `allowInsecure: true`, TLS sertifika doğrulamasını devre dışı bırakır ve
> bağlantıyı araya girme saldırılarına açık hâle getirir. Yalnızca gerçekten
> gerekli olduğunda kullanın. Değer `false` olduğunda standart sertifika
> doğrulaması değişmeden devam eder.

## Gereksinimler

- iOS 15 veya üzeri
- Swift 6 / Xcode 16 veya üzeri
- Packet Tunnel yeteneği etkinleştirilmiş Network Extension hedefi

İkili paket şu platform dilimlerini içerir:

- `ios-arm64`
- `ios-arm64_x86_64-simulator`

## Kurulum

Xcode içinde **File → Add Package Dependencies → Add Local...** yolunu izleyip
bu klasörü seçin. Ardından `SwiftyXrayKit` ürününü Packet Tunnel Extension
hedefine bağlayın.

## Hızlı başlangıç

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

Örnekteki `xrayConfigJSON`, outbound ve routing ayarlarını içeren geçerli bir
Xray JSON metnidir. `XrayBridge`, gerekli TUN inbound’unu bu yapılandırmaya
otomatik olarak ekler.

## Temel API

| API | Açıklama |
| --- | --- |
| `XrayBridge.start` | JSON veya paylaşım bağlantısından yapılandırma üretir ve Xray’i başlatır. |
| `XrayBridge.startWithRawConfig` | Önceden hazırlanmış Xray yapılandırmasını değiştirmeden çalıştırır. |
| `XrayBridge.buildConfig` | Xray’i çalıştırmadan üretilecek yapılandırmayı döndürür. |
| `XrayBridge.stop` | Xray’i durdurur ve socket pair’i kapatır. |
| `XrayBridge.getAndClearStats` | Son okumadan beri gönderilen/alınan baytları döndürür ve sayaçları sıfırlar. |
| `GeoFilesLoader.loadGeoFiles` | `geoip.dat` ve `geosite.dat` dosyalarını eşzamanlı indirir. |

### Paylaşım bağlantısı kullanımı

```swift
try bridge.start(
    config: .url("vless://..."),
    dataDir: dataDirectory,
    finalConfigPath: configPath
)
```

### Yapılandırmayı özelleştirme

`configTransform`, üretilen sözlüğü dosyaya yazılmadan önce değiştirmeyi sağlar:

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

### Geo dosyalarını indirme

```swift
let loader = GeoFilesLoader()

try await loader.loadGeoFiles(
    into: dataDirectory,
    geoSiteURL: nil,
    geoIPURL: nil
) { progress in
    print("İlerleme: \(Int(progress * 100))%")
}
```

Kararlı ve hızlı bir VPN başlangıcı için geo dosyalarını Packet Tunnel
Extension başlatılmadan önce indirip doğrulamak önerilir.

## Ayar profilleri

Paket iki hazır profil sunar:

- `.mobile`: iOS Network Extension bellek sınırlarına göre ayarlanmıştır.
- `.desktop`: daha yüksek bağlantı ve bellek limitleri kullanır.

Varsayılan profil iOS’ta `.mobile`, macOS’ta `.desktop` değeridir. Özel bir
profil de oluşturulabilir:

```swift
let preset = XrayTuningPreset(
    memoryLimitMB: 30,
    tcpBufMaxKB: 1024,
    tcpMaxInFlight: 512,
    udpMaxConns: 256,
    idleTimeoutSec: 120
)
```

## Güvenlik notları

- Üretimde mümkün olduğunca `allowInsecure: false` kullanın.
- Son Xray yapılandırması kullanıcı bilgileri veya anahtarlar içerebilir.
- `traceHandle`, tüm yapılandırmayı loglayabildiği için üretim loglarında
  kullanılmadan önce hassas alanlar maskelenmelidir.
- İndirilen geo dosyaları güvenilmeyen bir kaynaktan alınıyorsa bütünlük
  doğrulaması yapılmalıdır.

## Kaynak sürümleri

| Bileşen | Sürüm / commit |
| --- | --- |
| Xray-core | `v26.3.27` / `d2758a023cd7f4174a5a5fa4ff66e487d4342ba0` |
| libXray Apple wrapper | `v26.3.27-ios` / `7dd886449289adc0243bf8d51b8f1e0f693f038d` |
| SwiftyXrayKit | `2.0.0` / `3c5405521ae547de110f6ea65df00b1c05f6a0bc` |
| Go | `1.26.4` |

Yerel değişiklikler şu dosyalarda tutulur:

- `Patches/xray-core-ios-custom.patch`
- `Patches/libxray-apple-custom.patch`

## LibXray’i yeniden derleme

1. Xray-core deposunu yukarıdaki commit’te checkout edin ve Xray patch’ini uygulayın.
2. Apple wrapper deposunu yanına checkout edin ve wrapper patch’ini uygulayın.
3. Wrapper’ın Go module replacement ayarını patch uygulanmış Xray-core klasörüne yönlendirin.
4. `PATH="$HOME/go/bin:$PATH" python3 build/main.py apple gomobile` komutunu çalıştırın.
5. Cihaz ve simülatör framework’lerini `xcodebuild -create-xcframework` ile birleştirin.
6. Sonucu `LibXray.xcframework.zip` adıyla paketleyin.

Beklenen SHA-256:

```text
376e8401e8774b4f8f6a4db8cb1a55799aff0d28e337610bf30b789542279181
```

## Lisanslar

- `LICENSE-SwiftyXrayKit`
- `LICENSE-Xray-core`
- `LICENSE-libXray`
