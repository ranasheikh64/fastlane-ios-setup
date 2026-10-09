#!/bin/bash

# ==========================================
# Universal TestFlight Deploy Tool (Pro)
# ==========================================

# Colors for clear messaging
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}🚀 Flutter TestFlight Auto-Deploy Pro 🚀${NC}"
echo -e "${CYAN}==========================================${NC}\n"

# 1. Basic Project Validation
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: This does not look like a Flutter project.${NC}"
    echo "Please run this script from the root of your Flutter project."
    exit 1
fi

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Error: Flutter is not installed or not in your PATH.${NC}"
    exit 1
fi

# 2. Input Validation
read -p "Enter your App Store Connect Key ID: " API_KEY_ID < /dev/tty
read -p "Enter your App Store Connect Issuer ID: " ISSUER_ID < /dev/tty

if [ -z "$API_KEY_ID" ] || [ -z "$ISSUER_ID" ]; then
    echo -e "${RED}❌ Error: Key ID and Issuer ID cannot be empty!${NC}"
    exit 1
fi

# 3. .p8 File Validation
P8_FILE=$(find ./keys -name "*.p8" | head -n 1 2>/dev/null)

if [ -z "$P8_FILE" ]; then
    echo -e "${RED}❌ Error: No .p8 file found!${NC}"
    echo -e "${YELLOW}👉 Solution: Create a 'keys' folder in your project root and place your .p8 Auth Key inside it.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found Auth Key: $P8_FILE${NC}"

# 4. Setup Keys securely
DEST_DIR="$HOME/.appstoreconnect/private_keys"
mkdir -p "$DEST_DIR"
KEY_DEST_PATH="$DEST_DIR/AuthKey_${API_KEY_ID}.p8"

# Remove any old key with the same ID just in case
rm -f "$KEY_DEST_PATH"
cp "$P8_FILE" "$KEY_DEST_PATH"
chmod 600 "$KEY_DEST_PATH" # Secure the key

# 5. Build Flutter App
echo -e "\n${CYAN}📦 Step 1/2: Building iOS App (IPA)...${NC}"
echo -e "${YELLOW}(This might take a few minutes. Please wait...)${NC}"

# Try to build. If ExportOptions.plist exists, use it. Otherwise, rely on automatic signing.
if [ -f "ios/ExportOptions.plist" ]; then
    BUILD_CMD="flutter build ipa --release --export-options-plist=ios/ExportOptions.plist"
else
    BUILD_CMD="flutter build ipa --export-method app-store"
fi

if ! $BUILD_CMD; then
    echo -e "\n${RED}❌ Error: Build Failed!${NC}"
    echo -e "${YELLOW}👉 Common Reasons:${NC}"
    echo "1. Code signing is not properly set up in Xcode."
    echo "2. Your Apple Distribution Certificate or Provisioning Profile is missing/expired."
    echo "3. There are compile-time errors in your Flutter/Dart code."
    echo "Please open 'ios/Runner.xcworkspace' in Xcode and fix the errors first."
    
    rm -f "$KEY_DEST_PATH" # Cleanup
    exit 1
fi

# 6. IPA File Validation
IPA_FILE=$(find build/ios/ipa -name "*.ipa" | head -n 1 2>/dev/null)

if [ -z "$IPA_FILE" ]; then
    echo -e "\n${RED}❌ Error: Build succeeded but no .ipa file was generated!${NC}"
    rm -f "$KEY_DEST_PATH"
    exit 1
fi

echo -e "${GREEN}✅ Build successful! Found IPA at: $IPA_FILE${NC}"

# 7. Upload to TestFlight
echo -e "\n${CYAN}☁️  Step 2/2: Uploading to TestFlight...${NC}"
echo -e "${YELLOW}(Do not close the terminal. Uploading can take several minutes...)${NC}"

# Run altool and capture both stdout and stderr
UPLOAD_OUTPUT=$(xcrun altool --upload-app --type ios --file "$IPA_FILE" --apiKey "$API_KEY_ID" --apiIssuer "$ISSUER_ID" 2>&1)
UPLOAD_STATUS=$?

# 8. Clean up the key immediately after upload attempt
rm -f "$KEY_DEST_PATH"

# 9. Handle Upload Results
if [ $UPLOAD_STATUS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 SUCCESS! Your app has been uploaded to TestFlight.${NC}"
    echo "It may take 10-15 minutes for Apple to process it before it shows up in App Store Connect."
else
    echo -e "\n${RED}❌ Error: Upload Failed!${NC}"
    echo -e "${YELLOW}👉 Let's figure out what went wrong:${NC}\n"
    
    # Smart Error Analysis
    if echo "$UPLOAD_OUTPUT" | grep -qi "NOT_AUTHORIZED"; then
        echo -e "${RED}Authentication Issue:${NC} Your Key ID, Issuer ID, or .p8 file is incorrect or expired."
        echo "Make sure your Key has 'App Manager' or 'Admin' access in App Store Connect."
    elif echo "$UPLOAD_OUTPUT" | grep -qi "redundant"; then
        echo -e "${RED}Version Conflict:${NC} This exact Version and Build Number has already been uploaded."
        echo "👉 Solution: Go to your 'pubspec.yaml', increase the version number (e.g. from 1.0.0+1 to 1.0.0+2), and try again."
    elif echo "$UPLOAD_OUTPUT" | grep -qi "ITMS-"; then
        echo -e "${RED}App Store Rejection:${NC} Apple's servers rejected the app."
        echo "Check the detailed error below for the specific 'ITMS-' code."
    else
        echo -e "${RED}Unknown Network/Upload Error:${NC} Please check your internet connection."
    fi
    
    echo -e "\n${CYAN}--- Raw Apple Error Log ---${NC}"
    echo "$UPLOAD_OUTPUT"
    echo -e "${CYAN}---------------------------${NC}"
    exit 1
fi
