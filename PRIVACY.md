# Privacy Policy

**ClipStash — Clipboard History Manager**  
Last updated: November 18, 2026

---

## Summary

ClipStash stores clipboard history on your Mac. It has no built-in account,
clipboard sync, or usage analytics. Clipboard history and exported files can
contain any personal or sensitive information you copy.

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

- ClipStash does not ask for account details or location.
- It has no built-in usage analytics or crash reporting.

---

## How Data is Collected

Clipboard data is captured by monitoring `NSPasteboard.changeCount` every 300ms while the app is running. This is a standard macOS API for clipboard access.

**Automatic Protections:**
- The sensitive clipboard filters can omit content marked concealed or transient.
- These types depend on markers from the app that copied the content.
- User-specified applications can be excluded from capture

---

## Data Storage

All data is stored locally in:  
`~/Library/Application Support/ClipStash/`

| File | Contains |
|------|----------|
| `clipstash.db` | SQLite database with text entries |
| `images/` | Captured image files |

History and exports should be treated as sensitive files. Exports are written without app-level encryption.

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

Clipboard capture, search, and export run locally. The app can open external
product and support links when selected. Exported files are subject to the
storage and sharing settings of the folder you choose.

## Third-Party Services

ClipStash uses **no third-party services** or SDKs.

---

## Sensitive Data Handling

We understand clipboard managers handle sensitive data:

1. **Clipboard markers:** Concealed and transient filters depend on flags supplied by the source app.
2. **App exclusions:** Disable capture from configured apps in privacy settings.
3. **Exports:** Review history and exported files for sensitive content before sharing.

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
