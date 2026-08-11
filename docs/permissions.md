# Permissions

Orbis asks for access only when the operating system requires it for an RDP connection.

## iPadOS

| Permission or capability | Required | Why |
|---|---:|---|
| Local Network | Yes for LAN hosts | RDP connects directly to an IP address or hostname on the private network. `NSLocalNetworkUsageDescription` explains this before iPadOS shows its prompt. |
| Outbound internet access | No entitlement | iPadOS applications can open client TCP connections without a separate entitlement. This covers public DNS names, VPNs, and private-network agents. |
| Keychain | No prompt | Saved passwords use the application Keychain access group created by code signing. Passwords are not stored with connection profiles. |
| Paste from other apps | System-controlled | Clipboard redirection can make iPadOS show its standard paste confirmation when Orbis reads content written by another app. There is no usage-description key that bypasses this prompt. |
| Indirect input | Not a permission | `UIApplicationSupportsIndirectInputEvents` enables keyboard and pointer events. It does not grant access to other data. |

Orbis does not request camera, microphone, photos, contacts, location, Bluetooth, notifications, speech recognition, HomeKit, or motion access. Those APIs are not used by the Orbis iPad target.

## macOS

The direct macOS build declares `NSLocalNetworkUsageDescription` because macOS 15 can ask before a signed application reaches devices on the local network. Public TCP connections do not need a usage string.

The current direct-distribution build is not App Sandbox enabled. A future Mac App Store build will need exactly these sandbox entitlements:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

The first enables the sandbox required by the Mac App Store. The second permits outgoing RDP connections from that sandbox. Orbis does not need Screen Recording or Accessibility because the remote desktop is decoded inside the app and keyboard input is handled only while its own window is active. It does not capture the local display or control other applications.

The camera and microphone descriptions under `vendor/freerdp/client/Mac` belong
to the upstream FreeRDP client. Orbis uses `macos/Info.plist.in`, which does not
contain those permissions and does not enable device redirection.
