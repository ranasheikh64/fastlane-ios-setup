#!/bin/bash

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}🚀 Starting One-Click TestFlight Deploy...${NC}\n"

read -p "Enter your App Store Connect Key ID: " API_KEY_ID < /dev/tty
read -p "Enter your App Store Connect Issuer ID: " ISSUER_ID < /dev/tty

P8_FILE=$(find ./keys -name "*.p8" | head -n 1 2>/dev/null)

if [ -z "$P8_FILE" ]; then
    echo -e "${RED}❌ Error: No .p8 file found!${NC}"
    echo "Please create a 'keys' folder in your project root and place your .p8 file there."
    exit 1
fi

echo -e "${GREEN}✅ Found Auth Key: $P8_FILE${NC}"

DEST_DIR="$HOME/.appstoreconnect/private_keys"
mkdir -p "$DEST_DIR"
cp "$P8_FILE" "$DEST_DIR/AuthKey_${API_KEY_ID}.p8"

echo -e "${CYAN}📦 Building Flutter iOS App...${NC}"
flutter build ipa --export-method app-store

IPA_FILE=$(find build/ios/ipa -name "*.ipa" | head -n 1 2>/dev/null)

if [ -z "$IPA_FILE" ]; then
    echo -e "${RED}❌ Error: IPA build failed!${NC}"
    rm -f "$DEST_DIR/AuthKey_${API_KEY_ID}.p8"
    exit 1
fi

echo -e "${GREEN}✅ Build successful! Uploading to TestFlight...${NC}"

xcrun altool --upload-app \
  --type ios \
  --file "$IPA_FILE" \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$ISSUER_ID"

# Cleanup
rm -f "$DEST_DIR/AuthKey_${API_KEY_ID}.p8"

echo -e "\n${GREEN}🎉 Successfully Uploaded to TestFlight!${NC}"
