# 🍎 Flutter iOS Provisioning Setup

Automates **App Store certificate + provisioning profile** setup for Flutter iOS apps using Fastlane — so any developer can build and upload to TestFlight using a client's Apple Developer account **without needing their Apple ID or password**.

---

## ✅ What This Script Does

| Step | Action |
|------|--------|
| 0 | Auto-detects Flutter project root (or asks you) |
| 1–2 | Creates `AuthKey_XXXX.json` from your `.p8` key |
| 3 | Downloads Distribution Certificate via `fastlane cert` |
| 3b | Imports certificate into your macOS Keychain |
| 4 | Downloads Provisioning Profiles via `fastlane sigh` |
| 5 | Extracts Team ID from the certificate |
| 6–7 | Matches profiles installed in Xcode |
| 8 | Generates `ios/ExportOptions.plist` |

After the script completes, you get **two ready-to-run commands** to build your IPA and upload to TestFlight.

---

## 📋 Prerequisites

### macOS only
```bash
brew install fastlane openssl
```

### From your client's Apple Developer account
1. Go to [App Store Connect → Users → Keys](https://appstoreconnect.apple.com/access/integrations/api)
2. Create or download an **API Key** (role: App Manager or higher)
3. Note the **Key ID** (e.g. `LTG6TML48B`) and **Issuer ID**
4. Download the `.p8` file (you can only download it once)

---

## 🚀 Quick Start

### Step 1 — Place your `.p8` file
```
your-flutter-project/
└── fastlane/
    └── ios/
        └── AuthKey_XXXXXX.p8   ← put it here
```

```bash
mkdir -p fastlane/ios
mv ~/Downloads/AuthKey_XXXXXX.p8 fastlane/ios/
```

### Step 2 — Download & run the script

**Option A — Run directly from your Flutter project root:**
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/fastlane-ios-setup/main/ios_provision_setup.sh | bash
```

**Option B — Clone and run:**
```bash
git clone https://github.com/YOUR_USERNAME/fastlane-ios-setup.git
cd your-flutter-project
bash ../fastlane-ios-setup/ios_provision_setup.sh
```

**Option C — Download once, use for multiple projects:**
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/fastlane-ios-setup/main/ios_provision_setup.sh \
  -o ~/bin/ios_provision_setup.sh
chmod +x ~/bin/ios_provision_setup.sh

# then from any Flutter project:
ios_provision_setup.sh
```

---

## 🧪 Dry-Run Mode

Validates everything **without making any real changes** — no files created, no keychain touched:

```bash
./ios_provision_setup.sh --dry-run
```

Use this to verify your inputs and environment before the real run.

---

## 🔄 Rollback

If any step fails, the script **automatically rolls back**:
- Deletes the `AuthKey_XXXX.json` file
- Deletes downloaded `.cer` and `.mobileprovision` files
- Removes the imported certificate from your macOS Keychain
- Deletes `ExportOptions.plist`

You can safely re-run the script after fixing the issue.

---

## 📁 Files Created

```
your-flutter-project/
├── fastlane/
│   └── ios/
│       ├── AuthKey_XXXXXX.p8         (your input)
│       ├── AuthKey_XXXXXX.json       ← created by script
│       ├── XXXXXXXXXX.cer            ← distribution certificate
│       └── *.mobileprovision         ← provisioning profiles
├── ios/
│   └── ExportOptions.plist           ← created by script
└── logs/
    └── ios_setup_20240101_120000.log ← run log
```

---

## 🏗️ After Running — Build & Upload

The script prints these commands at the end:

**Build IPA:**
```bash
fastlane gym \
  --workspace './ios/Runner.xcworkspace' \
  --scheme 'Runner' \
  --configuration 'Release' \
  --clean \
  --export_method 'app-store' \
  --export_options './ios/ExportOptions.plist' \
  --output_directory './ios/build/ipa'
```

**Upload to TestFlight:**
```bash
fastlane pilot upload \
  --ipa './ios/build/ipa/Runner.ipa' \
  --api_key_path './fastlane/ios/AuthKey_XXXXXX.json' \
  --skip_waiting_for_build_processing
```

---

## 🔐 Security Notes

- The `.p8` file and generated `AuthKey_*.json` contain **private key material**
- Add both to `.gitignore`:
  ```gitignore
  fastlane/ios/*.p8
  fastlane/ios/*.json
  fastlane/ios/*.cer
  fastlane/ios/*.mobileprovision
  ios/ExportOptions.plist
  logs/
  ```
- Never commit these files to version control

---

## ❓ Troubleshooting

| Error | Fix |
|-------|-----|
| `fastlane cert` fails | Check Key ID, Issuer ID, and `.p8` file are correct |
| `No .mobileprovision file` | Verify bundle ID exists in App Store Connect |
| `No profiles in Xcode` | Xcode → Settings → Accounts → Download Manual Profiles |
| `Team ID not found` | Certificate may be corrupted — delete and re-run |
| `plutil: invalid plist` | Check for special characters in profile name |

---

## 🗂️ Project Structure

```
fastlane-ios-setup/
├── ios_provision_setup.sh   ← main script
└── README.md
```

---

## 📄 License

MIT — free to use, modify, and distribute.# fastlane-ios-setup
