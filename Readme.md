# Universal TestFlight Deploy Tool 🚀

A simple, one-click script to automatically build and upload your Flutter iOS app directly to TestFlight using your App Store Connect API Key (`.p8`), without needing complex Fastlane configurations.

## 🛠 Prerequisites
- You must be using a macOS device.
- Xcode and Flutter must be installed.
- Your iOS project must be configured with a valid Apple Distribution Certificate and App Store Provisioning Profile.

## 🚀 How to Use

You **don't need to download** anything manually! Just follow these 2 simple steps:

1. Create a `keys` folder in the root directory of your Flutter project and place your `.p8` (App Store Connect Auth Key) file inside it.
   ```
   your_flutter_project/
   ├── keys/
   │   └── AuthKey_XXXXXXX.p8
   ├── ios/
   ├── lib/
   └── pubspec.yaml
   ```

2. Open your terminal in the root of your Flutter project and run this command:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/ranasheikh64/fastlane-ios-setup/main/deploy.sh)
   ```

3. The script will ask for your **Key ID** and **Issuer ID**. Once provided, it will automatically:
   - Move your key to the secure App Store Connect folder.
   - Build your Flutter iOS app (`flutter build ipa`).
   - Find the `.ipa` file and upload it directly to TestFlight using `altool`.
   - Safely clean up the private key when finished.

## 🎉 Done!
Your app will now be processed in TestFlight.
