# Developing Perch

## Layout of the code

| File | Role |
|---|---|
| `main.swift` | Entry point; runs as an accessory (menu-bar-only) app |
| `AppDelegate.swift` | Menu bar, Accessibility permission flow, wiring |
| `DragMonitor.swift` | `CGEventTap` state machine that detects real window drags |
| `Overlay.swift` | Click-through panel: icon strip, hover footprint, hit testing |
| `ZoneRenderer.swift` | Draws one icon; shared by the overlay and the editor |
| `LayoutEditor.swift` | Settings window |
| `GridEditorView.swift` | Drag-to-select grid |
| `AX.swift` | Accessibility reads and writes |
| `Zones.swift` | Zone model, config, JSON persistence |
| `Geometry.swift` | Cocoa ↔ Quartz coordinate conversion |
| `Log.swift` | Opt-in debug logging |

## Two things that will bite you

### 1. Coordinate systems

macOS uses two, and they disagree about which way is up.

- **Cocoa** (`NSScreen`, `NSWindow`, `NSView`): origin bottom-left of the
  primary display, y increases upwards.
- **Quartz / Accessibility** (`CGEvent.location`, `kAXPosition`): origin
  top-left, y increases downwards.

Everything that touches a window is Quartz. Everything that draws is Cocoa.
`Geometry.swift` is the only place that flips between them — keep it that way.

### 2. Code signing and Accessibility

An **ad-hoc** signature's designated requirement pins the code hash:

```
designated => cdhash H"5966..."
```

That hash changes on every build, so macOS silently revokes Accessibility
access — while System Settings still shows the toggle **on**, because that list
is keyed by bundle path. The app then appears broken: drags produce no icons.

Fix it once with a stable self-signed certificate:

```bash
cat > /tmp/perch-cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = Perch Development
[v3]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /tmp/perch-key.pem -out /tmp/perch-cert.pem \
  -config /tmp/perch-cert.cnf -extensions v3

# -certpbe/-keypbe/-macalg are required: OpenSSL 3 defaults produce a PKCS#12
# that Apple's `security` tool cannot read.
openssl pkcs12 -export -inkey /tmp/perch-key.pem -in /tmp/perch-cert.pem \
  -name "Perch Development" -out /tmp/perch.p12 -passout pass:perch \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

security import /tmp/perch.p12 -k ~/Library/Keychains/login.keychain-db -P perch -A
```

`build.sh` picks it up automatically. The requirement becomes

```
designated => identifier "com.zhanli.perch" and certificate leaf = H"05c2..."
```

which is stable across rebuilds. Note `security find-identity -v -p codesigning`
will still report **0 valid identities** because the certificate is untrusted —
that is fine, `codesign` uses it anyway and TCC only cares about the
requirement.

If you swap the certificate or bundle ID, clear the stale grant:

```bash
tccutil reset Accessibility com.zhanli.perch
```

## Debug logging

```bash
defaults write com.zhanli.perch debug -bool true
# reproduce, then:
cat /tmp/perch-debug.log
defaults write com.zhanli.perch debug -bool false
```

Drops are logged with the target app, whether position and size were
individually settable, whether `AXEnhancedUserInterface` was on, any `AXError`
codes, and before/after frames.

## Why windows sometimes move but refuse to resize

Two causes, both handled in `AX.setFrame`:

1. **`AXEnhancedUserInterface`.** Apps with it on — Electron and Java apps
   commonly, and any app after VoiceOver has run — animate programmatic
   geometry changes and drop the resize while still honouring the move. It has
   to be switched off around the write and restored after.
2. **Clamping order.** An app asked to move to the left edge at its old width
   may refuse; asked to resize first, it may refuse a size that would overhang
   the right edge. Writing **size, position, size** satisfies both, and ending
   on a size write gives a clamped resize a second attempt from the right spot.

A genuine third case is not a bug: apps with a minimum width larger than the
target simply cannot comply. The debug log distinguishes these —
`sizeSettable=false` means refusal, `sizeSettable=true` with a mismatched
`after` frame means clamping.

## Releasing

```bash
./build.sh
cd build && zip -r Perch-1.0.0.zip Perch.app
```

Attach the zip to a GitHub release. If you later get an Apple Developer ID,
set `PERCH_SIGN_IDENTITY` and add notarisation — `notarytool` and `stapler`
ship with Command Line Tools, so no Xcode is needed:

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: NAME (TEAMID)" build/Perch.app
xcrun notarytool submit Perch-1.0.0.zip --keychain-profile "perch-notary" --wait
xcrun stapler staple build/Perch.app
```
