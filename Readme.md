# 🚀 Jronix iOS TestFlight Publish

A fully automated, zero-headache Bash script for Flutter developers to handle iOS Provisioning, Code Signing, and TestFlight Deployment using Fastlane.

Powered by **Jronix Development Team** ⚡️.

## ✨ Features
- **Auto Project Detection**: Automatically finds your Flutter project root.
- **One-Command Setup**: Downloads distribution certificates and provisioning profiles automatically.
- **Auto Fastlane Integration**: Generates the required API key JSON and `ExportOptions.plist`.
- **One-Click Build & Upload**: Interactively builds the `.ipa` and uploads it to TestFlight without leaving the terminal.
- **Safe Rollback**: Automatically cleans up generated keys and certificates if any step fails.

---

## 🛠 Prerequisites

Before running the script, make sure you have the following installed on your Mac:
- **macOS** (Required for iOS builds)
- **Xcode** (Installed from Mac App Store)
- **Fastlane** (`brew install fastlane`)
- **CocoaPods** (`brew upgrade cocoapods`)

---

## 🔑 Getting the Client's API Key & Permissions

To publish an app on behalf of a client, you need an **App Store Connect API Key (`.p8` file)** from their Apple Developer Account. 

### What permission do you need?
Tell your client to generate an API Key with **Admin** or **App Manager** access in their App Store Connect account.

### How to generate the `.p8` file (Share these steps with your client):
1. Log in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Go to **Users and Access** > **Keys** (tab).
3. Click the **+** button to add a new key.
4. **Name**: Enter any name (e.g., "Jronix Fastlane Key").
5. **Access**: Select **Admin** or **App Manager**.
6. Click **Generate**.
7. Click **Download API Key** to get the `.p8` file (e.g., `AuthKey_XXXXXXXXXX.p8`). 
   *(⚠️ Note: Apple only allows downloading this file ONCE. Keep it safe.)*
8. Note down the **Issuer ID** and **Key ID** shown on that page (you will need to provide these to the script).

---

## 🚀 How to Use

### Step 1: Place your Key File
In your Flutter project, create a folder named `fastlane/ios/` and drop your `.p8` file inside:
```text
your_flutter_project/
├── lib/
├── ios/
├── fastlane/
│   └── ios/
│       └── AuthKey_XXXXXXXXXX.p8   <-- Place it here
└── pubspec.yaml
```

*(Note: Don't forget to add `fastlane/ios/AuthKey_*.json` and `*.p8` to your `.gitignore` to keep them secure!)*

### Step 2: Run the Automation Script
Open your terminal, go to your Flutter project folder, and run this single command:

```bash
bash <(curl -s https://raw.githubusercontent.com/ranasheikh64/fastlane-ios-setup/main/fastlane_ios_setup.sh)
```

### Step 3: Follow the Prompts
The script will ask you for a few details:
1. **Key ID**: (The 10-character ID of your `.p8` file, e.g., CHTVK57497)
2. **Issuer ID**: (The long UUID from App Store Connect)
3. **Bundle ID**: (Your app's bundle ID, e.g., `com.jronix.myapp`)

After entering these, the script will automatically:
✅ Create the necessary AuthKey JSON.
✅ Download the Apple Distribution Certificate.
✅ Download the App Store Provisioning Profiles.
✅ Build the `.ipa` file using `fastlane gym`.
✅ Upload it directly to TestFlight using `fastlane pilot`.

---

## ⚠️ Troubleshooting (CocoaPods)

If your app fails to build (`ARCHIVE FAILED`) and you see errors regarding `PrivacyInfo.xcprivacy`, it means your project has old, cached CocoaPods files. 

Run this to fix it before running the script again:
```bash
flutter clean
flutter pub get
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
```

---

*Thank you for using Jronix Automation Tools!*  
*Built with ❤️ by Jronix Development Team.*
