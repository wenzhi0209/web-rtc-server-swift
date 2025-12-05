# WebRTC HTTPS Server for iOS

A native iOS app that runs an HTTPS server to enable WebRTC peer-to-peer communication between devices. Since WebRTC requires a secure context (HTTPS), this app provides a simple way to host WebRTC signaling pages directly from your iPhone.

## Why This Exists

WebRTC APIs (`RTCPeerConnection`, `getUserMedia`, etc.) only work in secure contexts:
- `https://` URLs
- `localhost`

When testing WebRTC between devices on a local network, you need an HTTPS server. This app turns your iPhone into that server.

## Features

- Native HTTPS server using Apple's Network framework
- Self-signed TLS certificate support
- Real-time connection logging
- Auto-detects WiFi IP address
- Built-in WebRTC signaling page for manual offer/answer exchange
- Copy server URL with one tap

## Requirements

- iOS 15.0+
- Xcode 15+
- A self-signed certificate (`server.p12`)

## Setup

### 1. Generate Self-Signed Certificate

```bash
# Generate private key and certificate
openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes \
  -subj "/CN=WebRTC Server"

# Convert to PKCS12 format
openssl pkcs12 -export -out server.p12 -inkey server.key -in server.crt -passout pass:123456
```

### 2. Add Certificate to Project

1. Drag `server.p12` into Xcode project
2. Ensure "Copy items if needed" is checked
3. Add to target "WebRTCServer"

### 3. Build and Run

Open `WebRTCServer.xcodeproj` in Xcode and run on your iPhone.

## Usage

### Starting the Server

1. Launch the app on your iPhone
2. Tap **Start** button
3. The server URL will be displayed (e.g., `https://192.168.1.100:8443/`)
4. Tap **Copy Address** to copy the URL

### Accessing from Browser

1. Open the URL in a browser on another device (same WiFi network)
2. Accept the certificate warning (self-signed cert)
3. The WebRTC signaling page will load

### WebRTC Connection Flow

The built-in page supports manual WebRTC signaling:

```
Device A (Initiator)          Device B (Receiver)
       |                            |
       |  1. Create Offer           |
       |--------------------------->|
       |     (copy/paste)           |
       |                            |
       |  2. Accept & Create Answer |
       |<---------------------------|
       |     (copy/paste)           |
       |                            |
       |  3. Accept Answer          |
       |                            |
       |  4. Connected! 🎉          |
       |<=========================>|
       |    (P2P DataChannel)       |
```

1. **Device A**: Click "Create Offer", copy the generated text
2. **Device B**: Paste offer, click "Accept and Generate Answer", copy the answer
3. **Device A**: Paste answer, click "Complete Connection"
4. Both devices can now send messages via WebRTC DataChannel

## Project Structure

```
WebRTCServer/
├── WebRTCServerApp.swift    # App entry point
├── ContentView.swift        # Main UI and HTTPS server logic
├── webRTC.html             # WebRTC signaling page
├── Info.plist              # App configuration
└── Assets.xcassets/        # App icons and colors
```

## Technical Details

### HTTPS Server

- Uses `NWListener` from Network framework
- TLS 1.2+ with self-signed certificate
- Runs on port 8443
- Serves static HTML content

### WebRTC Page

- Pure JavaScript, no external dependencies
- Manual SDP offer/answer exchange
- RTCDataChannel for text messaging
- Requests microphone permission to get real ICE candidates (not mDNS)

## Troubleshooting

### "Certificate Error" in Browser

This is expected with self-signed certificates. Click "Advanced" → "Proceed anyway" (Chrome) or "Continue" (Safari).

### Server Won't Start

- Ensure `server.p12` is added to the project bundle
- Check that password in code matches certificate password (`123456`)
- Verify iPhone is connected to WiFi

### WebRTC Connection Fails

- Both devices must be on the same network
- Grant microphone permission when prompted (needed for real IP candidates)
- Check firewall settings on the network

## License

MIT
