# Privacy Policy

**ClipStash — Clipboard History Manager**  
Last updated: December 8, 2024

---

## Summary

ClipStash is a **100% local, privacy-first** clipboard manager. We collect **no personal data**, make **no network requests**, and store all clipboard history **only on your device**.

---

## Data Collection

### What We Store

| Data Type | Stored | Location | Purpose |
|-----------|--------|----------|---------|
| Clipboard text | ✅ Yes | Local only | History recall |
| Clipboard images | ✅ Yes (optional) | Local only | History recall |
| Source app bundle ID | ✅ Yes | Local only | Filtering |
| Timestamps | ✅ Yes | Local only | Sorting |
| User preferences | ✅ Yes | Local only | App settings |

### What We Do NOT Collect

- ❌ Personal identifiers (name, email, phone)
- ❌ Device identifiers
- ❌ Location data
- ❌ Usage analytics
- ❌ Crash reports
- ❌ Any data transmitted over the network

---

## How Data is Collected

Clipboard data is captured by monitoring `NSPasteboard.changeCount` every 300ms while the app is running. This is a standard macOS API for clipboard access.

**Automatic Protections:**
- Password manager content (marked as `org.nspasteboard.ConcealedType`) is ignored by default
- Transient clipboard content (marked as `org.nspasteboard.TransientType`) is ignored by default
- User-specified applications can be excluded from capture

---

## Data Storage

All data is stored locally in:  
`~/Library/Application Support/ClipStash/`

| File | Contains |
|------|----------|
| `clipstash.db` | SQLite database with text entries |
| `images/` | Captured image files |

**Encryption:** Optional AES-GCM encryption is available for pinned items using keys stored in macOS Keychain.

---

## Data Retention

| Policy | Default |
|--------|---------|
| Maximum items | 500 (configurable: 100-2000) |
| Automatic cleanup | Oldest items removed when limit reached |
| Pinned items | Never auto-deleted |
| Images | Follow same retention as text |

---

## Your Rights

### Access Your Data
All your data is stored locally and can be accessed at:  
`~/Library/Application Support/ClipStash/`

### Delete Your Data
You have multiple options:

1. **In-App:** Settings → Advanced → "Clear All History"
2. **Keep Pinned:** Clear all except pinned items
3. **Complete Removal:** Delete the app and run:
   ```bash
   rm -rf ~/Library/Application\ Support/ClipStash
   ```

### Revoke Consent
Simply quit and uninstall ClipStash. No data persists elsewhere.

---

## Network Usage

**ClipStash makes ZERO network requests.**

- No analytics
- No telemetry
- No update checks
- No cloud sync
- No crash reporting

This is enforced by macOS App Sandbox (when enabled).

---

## Third-Party Services

ClipStash uses **no third-party services** or SDKs.

---

## Sensitive Data Handling

We understand clipboard managers handle sensitive data:

1. **Passwords:** Content from password managers (1Password, Bitwarden, etc.) is automatically excluded via `ConcealedType` detection
2. **User Control:** You can disable capture from any app via Settings → Privacy → Ignored Apps
3. **No Transmission:** Data never leaves your device
4. **Local Encryption:** Optional for pinned items

---

## Children's Privacy

ClipStash does not collect any personal information from anyone, including children under 13.

---

## Changes to This Policy

We will update this policy if our data practices change. Updates will be reflected in the "Last updated" date.

---

## Contact

For privacy questions or concerns:

- **Website:** https://kikuai.dev
- **GitHub:** https://github.com/kiku-jw/ClipStash
- **Email:** privacy@kikuai.dev

---

## Apple App Store Compliance

This app complies with Apple's App Store Review Guidelines regarding:
- **Section 5.1.1:** Data Collection and Storage — all data is local
- **Section 5.1.2:** Data Use and Sharing — no sharing occurs
- **Section 5.1.3:** Health and Fitness Data — not applicable
- **Section 5.1.4:** Kids — no data collection

---

*By using ClipStash, you acknowledge that clipboard history is stored locally on your device for your personal use.*
