#!/usr/bin/env bash
# =============================================================================
#  ios_provision_setup.sh
#  Flutter iOS — App Store Provisioning & Certificate Setup via Fastlane
#
#  USAGE:
#    chmod +x ios_provision_setup.sh
#    ./ios_provision_setup.sh              # normal run
#    ./ios_provision_setup.sh --dry-run    # validate only, no changes
#
#  REQUIREMENTS (macOS only):
#    brew install fastlane openssl
#
#  BEFORE RUNNING:
#    Place your .p8 key file inside  fastlane/ios/  relative to your
#    Flutter project root  (e.g.  fastlane/ios/AuthKey_XXXXXX.p8)
#
#  GitHub: https://github.com/ranasheikh64/fastlane-ios-setup
# =============================================================================

set -eo pipefail    # exit on error, pipe failure

# ── Script version ─────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.0.1"
TOTAL_STEPS=7

# ── Flags ──────────────────────────────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-d) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--help]"
      echo "  --dry-run   Validate everything without making any real changes"
      echo "  --help      Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg  (use --help)"
      exit 1
      ;;
  esac
done

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';      RESET='\033[0m'
DRY_TAG="${YELLOW}[DRY-RUN]${RESET} "

# ── Logging ────────────────────────────────────────────────────────────────────
LOG_DIR=""         # set after project root is confirmed
LOG_FILE=""

_log_raw() {
  local msg="$1"
  echo -e "$msg"
  # strip ANSI for log file
  if [ -n "$LOG_FILE" ]; then
    echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
  fi
}

log_step()    { _log_raw "\n${BOLD}${CYAN}▶ $1${RESET}"; }
log_success() { _log_raw "${GREEN}✅ $1${RESET}"; }
log_warn()    { _log_raw "${YELLOW}⚠️  $1${RESET}"; }
log_info()    { _log_raw "${CYAN}ℹ️  $1${RESET}"; }
log_error()   { _log_raw "${RED}❌ ERROR: $1${RESET}"; }
log_fatal() {
  log_error "$1"
  _log_raw "${RED}Script stopped. Check log: $LOG_FILE${RESET}"
  _rollback
  exit 1
}
log_dry() { _log_raw "${DRY_TAG}$1"; }

# ── Progress bar ───────────────────────────────────────────────────────────────
show_progress() {
  local COMPLETED=$1 TOTAL=$2 LABEL=$3
  local BAR_WIDTH=40
  local FILLED=$(( COMPLETED * BAR_WIDTH / TOTAL ))
  local EMPTY=$(( BAR_WIDTH - FILLED ))
  local BAR=""
  for ((i=0; i<FILLED; i++)); do BAR+="█"; done
  for ((i=0; i<EMPTY;  i++)); do BAR+="░"; done
  local PCT=$(( COMPLETED * 100 / TOTAL ))
  _log_raw "\n${BOLD}Progress: [${GREEN}${BAR}${RESET}${BOLD}] ${PCT}% — Step ${COMPLETED}/${TOTAL}: ${LABEL}${RESET}\n"
}

# ── Rollback tracker ───────────────────────────────────────────────────────────
# Files/dirs created by this script — removed on failure
ROLLBACK_FILES=()
ROLLBACK_KEYCHAIN_CERTS=()   # cert SHA-1 hashes imported into keychain

_rollback() {
  if [ ${#ROLLBACK_FILES[@]} -eq 0 ] && [ ${#ROLLBACK_KEYCHAIN_CERTS[@]} -eq 0 ]; then
    return
  fi
  _log_raw "\n${YELLOW}🔄 Rolling back changes...${RESET}"

  for f in "${ROLLBACK_FILES[@]}"; do
    if [ -e "$f" ]; then
      rm -f "$f" && _log_raw "  ${YELLOW}Removed: $f${RESET}" || true
    fi
  done

  for sha in "${ROLLBACK_KEYCHAIN_CERTS[@]}"; do
    security delete-certificate -Z "$sha" 2>/dev/null \
      && _log_raw "  ${YELLOW}Removed keychain cert: $sha${RESET}" || true
  done

  _log_raw "${YELLOW}Rollback complete.${RESET}"
}

# trap so rollback also fires on Ctrl+C / unexpected exit
trap '_rollback' ERR

# ── macOS guard ────────────────────────────────────────────────────────────────
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo -e "${RED}❌ This script requires macOS.${RESET}"
  exit 1
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   Flutter iOS Provisioning Setup  v${SCRIPT_VERSION}             ║${RESET}"
if $DRY_RUN; then
echo -e "${BOLD}${YELLOW}║              ⚠️  DRY-RUN MODE — no changes             ║${RESET}"
fi
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# =============================================================================
# STEP 0 — Locate Flutter project root
# =============================================================================
log_step "STEP 0: Locating Flutter project root"

PROJECT_ROOT=""
_locate_project_root() {
  # 1. Try current directory
  if [ -f "pubspec.yaml" ]; then
    PROJECT_ROOT="$(pwd)"
    return 0
  fi
  # 2. Check if we're inside a Flutter project subdirectory (up to 3 levels)
  local CHECK="$(pwd)"
  for _ in 1 2 3; do
    CHECK="$(dirname "$CHECK")"
    if [ -f "$CHECK/pubspec.yaml" ]; then
      PROJECT_ROOT="$CHECK"
      return 0
    fi
  done
  return 1
}

if _locate_project_root; then
  log_success "Auto-detected Flutter project root: $PROJECT_ROOT"
else
  while true; do
    read -rp "$(echo -e "${BOLD}Enter full path to your Flutter project root (contains pubspec.yaml): ${RESET}")" INPUT_PATH
    INPUT_PATH=$(echo "$INPUT_PATH" | xargs)
    INPUT_PATH="${INPUT_PATH%/}"
    [ -z "$INPUT_PATH" ] && log_warn "Path cannot be empty." && continue
    [ ! -d "$INPUT_PATH" ]          && log_error "Directory not found: $INPUT_PATH" && continue
    [ ! -f "$INPUT_PATH/pubspec.yaml" ] && log_error "pubspec.yaml not found in: $INPUT_PATH" && continue
    PROJECT_ROOT="$INPUT_PATH"
    break
  done
  log_success "Project root confirmed: $PROJECT_ROOT"
fi

cd "$PROJECT_ROOT" || { echo "Failed to cd into project root"; exit 1; }

# ── Init logging (now that we have project root) ───────────────────────────────
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/ios_setup_${TIMESTAMP}.log"
touch "$LOG_FILE"
log_info "Log file: $LOG_FILE"
$DRY_RUN && log_dry "Dry-run mode active — no real changes will be made."

# =============================================================================
# STEP 0b — Check required tools
# =============================================================================
log_step "STEP 0b: Checking required tools"

MISSING_TOOLS=()
command -v fastlane >/dev/null 2>&1 || MISSING_TOOLS+=("fastlane  → brew install fastlane")
command -v openssl  >/dev/null 2>&1 || MISSING_TOOLS+=("openssl   → brew install openssl")
command -v security >/dev/null 2>&1 || MISSING_TOOLS+=("security  → built-in macOS, should exist")
command -v plutil   >/dev/null 2>&1 || MISSING_TOOLS+=("plutil    → built-in macOS, should exist")

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  log_error "Missing required tools:"
  for t in "${MISSING_TOOLS[@]}"; do echo -e "   ${RED}• $t${RESET}"; done
  log_fatal "Install the tools above and re-run."
fi
log_success "All required tools found (fastlane, openssl, security, plutil)."

# =============================================================================
# STEP 0c — Check fastlane/ios/ exists
# =============================================================================
if [ ! -d "fastlane/ios" ]; then
  log_fatal "fastlane/ios/ directory not found.\nCreate it with:  mkdir -p fastlane/ios\nThen place your .p8 file inside it."
fi

# =============================================================================
# STEP 0d — Find & validate .p8 file
# =============================================================================
log_step "STEP 0d: Checking for .p8 key file in fastlane/ios/"

P8_FILE=$(find fastlane/ios/ -maxdepth 1 -name "*.p8" | head -n 1)
KEY_CONTENT=""
P8_FOUND=false
EG_AUTH_KEY=""

_format_key_content() {
  # Convert multiline PEM key → single string with literal \n separators
  # (required by App Store Connect JSON format)
  local RAW
  RAW=$(echo "$1" | tr -d '\r' | sed 's/[[:space:]]*$//')
  echo "$RAW" | awk 'NR==1{printf "%s\\n",$0; next} {printf "\\n%s",$0} END{printf ""}'
}

if [ -n "$P8_FILE" ]; then
  log_success "Found .p8 file: $P8_FILE"
  RAW_KEY=$(cat "$P8_FILE")
  KEY_CONTENT=$(_format_key_content "$RAW_KEY")

  if echo "$KEY_CONTENT" | grep -q "BEGIN PRIVATE KEY" && echo "$KEY_CONTENT" | grep -q "END PRIVATE KEY"; then
    log_success "Key content loaded and validated."
    P8_FOUND=true
    P8_BASENAME=$(basename "$P8_FILE" .p8)
    [[ "$P8_BASENAME" == AuthKey_* ]] && EG_AUTH_KEY="${P8_BASENAME#AuthKey_}"
  else
    log_warn ".p8 file doesn't look like a valid EC private key — will ask for manual paste."
  fi
else
  log_warn "No .p8 file found in fastlane/ios/ — you will paste the key manually."
fi

# =============================================================================
# COLLECT ALL INPUTS UPFRONT
# =============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}       iOS PROVISIONING SETUP — INPUT REQUIRED          ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo ""

# ── Input 1: Key ID ────────────────────────────────────────────────────────────
while true; do
  if [ -n "$EG_AUTH_KEY" ]; then
    read -rp "$(echo -e "${BOLD}[1] App Store Connect Key ID (ENTER to use ${CYAN}${EG_AUTH_KEY}${RESET}${BOLD}): ${RESET}")" AUTHKEY
  else
    read -rp "$(echo -e "${BOLD}[1] App Store Connect Key ID (e.g. CHTVK57497): ${RESET}")" AUTHKEY
  fi
  AUTHKEY=$(echo "$AUTHKEY" | xargs)
  if [ -z "$AUTHKEY" ]; then
    [ -n "$EG_AUTH_KEY" ] && AUTHKEY="$EG_AUTH_KEY" && log_success "Using key ID from filename: $AUTHKEY" && break
    log_warn "Key ID cannot be empty."
  else
    log_success "Key ID: $AUTHKEY"; break
  fi
done

# ── Input 2: Issuer ID ─────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}[2] App Store Connect Issuer ID (e.g. 57457fac-42ff-...): ${RESET}")" ISSUER_ID
  ISSUER_ID=$(echo "$ISSUER_ID" | xargs)
  if [ -z "$ISSUER_ID" ]; then
    log_warn "Issuer ID cannot be empty. Find it at appstoreconnect.apple.com → Users → Keys."
  else
    log_success "Issuer ID: $ISSUER_ID"; break
  fi
done

# ── Input 3: Key content (only if .p8 not auto-loaded) ────────────────────────
if [ "$P8_FOUND" = false ]; then
  echo ""
  echo -e "${BOLD}[3] Paste your full .p8 private key content below.${RESET}"
  echo -e "${YELLOW}    Start with: -----BEGIN PRIVATE KEY-----${RESET}"
  echo -e "${YELLOW}    When done, type END_KEY on a new line and press ENTER:${RESET}"
  RAW_PASTED=""
  while IFS= read -r line; do
    [ "$line" = "END_KEY" ] && break
    RAW_PASTED+="${line}"$'\n'
  done
  KEY_CONTENT=$(_format_key_content "$RAW_PASTED")
  if [ -z "$KEY_CONTENT" ] || ! echo "$KEY_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
    log_fatal "Key content is empty or invalid."
  fi
  log_success "Key content captured."
fi

# ── Input 4: Bundle IDs ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4] Enter Bundle ID(s) one by one.${RESET}"
echo -e "${YELLOW}    Press ENTER with empty input when done.${RESET}"
echo -e "${YELLOW}    Example: com.company.myapp${RESET}"
PACKAGE_NAMES=()
while true; do
  IDX=$((${#PACKAGE_NAMES[@]} + 1))
  read -rp "  Bundle ID #${IDX} (empty = done): " PKG
  PKG=$(echo "$PKG" | xargs)
  [ -z "$PKG" ] && [ ${#PACKAGE_NAMES[@]} -gt 0 ] && break
  [ -z "$PKG" ] && log_warn "Enter at least one bundle ID." && continue
  # basic format check
  if ! echo "$PKG" | grep -qE '^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}$'; then
    log_warn "That doesn't look like a valid bundle ID (e.g. com.company.app). Try again."
    continue
  fi
  PACKAGE_NAMES+=("$PKG")
  log_success "Added: $PKG"
done

# ── Summary + confirm ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}                   INPUT SUMMARY                        ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "  ${CYAN}Key ID:${RESET}     $AUTHKEY"
echo -e "  ${CYAN}Issuer ID:${RESET}  $ISSUER_ID"
echo -e "  ${CYAN}Key:${RESET}        [loaded — $(echo "$KEY_CONTENT" | wc -c | xargs) chars]"
echo -e "  ${CYAN}Bundles:${RESET}"
for pkg in "${PACKAGE_NAMES[@]}"; do echo -e "    ${YELLOW}• $pkg${RESET}"; done
$DRY_RUN && echo -e "\n  ${YELLOW}⚠️  DRY-RUN — no actual changes will be made.${RESET}"
echo ""
read -rp "$(echo -e "${BOLD}Confirm and start? (y/n): ${RESET}")" CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted." && exit 0

# =============================================================================
# STEP 1 — Enter fastlane/ios/
# =============================================================================
log_step "STEP 1/${TOTAL_STEPS}: Entering fastlane/ios/"

cd fastlane/ios/ || log_fatal "Failed to cd into fastlane/ios/"
log_success "Now in: $(pwd)"
show_progress 1 $TOTAL_STEPS "Entered fastlane/ios/"

# =============================================================================
# STEP 2 — Create AuthKey JSON
# =============================================================================
log_step "STEP 2/${TOTAL_STEPS}: Creating AuthKey_${AUTHKEY}.json"

JSON_FILE="AuthKey_${AUTHKEY}.json"

if $DRY_RUN; then
  log_dry "Would create: fastlane/ios/$JSON_FILE"
else
  cat > "$JSON_FILE" <<EOF
{
  "key_id": "$AUTHKEY",
  "issuer_id": "$ISSUER_ID",
  "key": "$KEY_CONTENT",
  "in_house": false
}
EOF
  [ ! -f "$JSON_FILE" ] && log_fatal "Failed to create $JSON_FILE"
  ROLLBACK_FILES+=("$(pwd)/$JSON_FILE")
  log_success "Created $JSON_FILE"
fi
show_progress 2 $TOTAL_STEPS "Created API key JSON"

# =============================================================================
# STEP 3 — fastlane cert
# =============================================================================
log_step "STEP 3/${TOTAL_STEPS}: Downloading distribution certificate (fastlane cert)"

CERTNAME=""
NEW_CER_FILE=""

if $DRY_RUN; then
  log_dry "Would run: fastlane cert --api_key_path $JSON_FILE"
  CERTNAME="DRY_RUN_CERT"
else
  CERT_OUTPUT=$(fastlane cert --api_key_path "$JSON_FILE" 2>&1)
  echo "$CERT_OUTPUT"

  NEW_CER_FILE=$(find . -maxdepth 1 -name "*.cer" -newer "$JSON_FILE" | head -n 1)

  if [ -z "$NEW_CER_FILE" ]; then
    if echo "$CERT_OUTPUT" | grep -q "installed on the local machine"; then
      CERTNAME=$(echo "$CERT_OUTPUT" | grep -oE 'certificate [A-Z0-9]+' | awk '{print $2}' | head -n 1)
      EXISTING_CER=$(find . -maxdepth 1 -name "${CERTNAME}.cer" | head -n 1)
      [ -n "$EXISTING_CER" ] && NEW_CER_FILE="$EXISTING_CER" && log_warn "Certificate already existed locally: $NEW_CER_FILE" \
        || log_fatal "fastlane cert reported existing cert but .cer file not found for '$CERTNAME'."
    else
      log_fatal "fastlane cert did not produce a .cer file."
    fi
  fi

  CERTNAME=$(basename "$NEW_CER_FILE" .cer)
  ROLLBACK_FILES+=("$(pwd)/$NEW_CER_FILE")
  log_success "Certificate ready: $CERTNAME"
fi

# =============================================================================
# STEP 3b — Import cert into keychain
# =============================================================================
log_step "STEP 3b/${TOTAL_STEPS}: Importing certificate into macOS keychain"

if $DRY_RUN; then
  log_dry "Would import $CERTNAME.cer into login keychain."
else
  KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
  IMPORT_OUT=$(security import "$NEW_CER_FILE" -k "$KEYCHAIN_PATH" 2>&1) && {
    # Track SHA-1 for rollback
    SHA=$(openssl x509 -in "$NEW_CER_FILE" -inform DER -fingerprint -noout 2>/dev/null \
          | sed 's/.*Fingerprint=//;s/://g' || true)
    [ -n "$SHA" ] && ROLLBACK_KEYCHAIN_CERTS+=("$SHA")
    log_success "Certificate imported into keychain."
  } || log_warn "Keychain import failed or cert already exists — continuing."
fi

show_progress 3 $TOTAL_STEPS "Certificate obtained: $CERTNAME"

# =============================================================================
# STEP 4 — fastlane sigh (provisioning profiles)
# =============================================================================
log_step "STEP 4/${TOTAL_STEPS}: Downloading provisioning profiles (fastlane sigh)"

FAILED_PACKAGES=()
MATCHED_KEYS=()
MATCHED_VALUES=()

for PKG in "${PACKAGE_NAMES[@]}"; do
  echo ""
  echo -e "${CYAN}  → Processing: $PKG${RESET}"

  if $DRY_RUN; then
    log_dry "Would run: fastlane sigh --api_key_path $JSON_FILE -a $PKG"
    continue
  fi

  TMP_MARKER=$(mktemp)
  SIGH_OUTPUT=$(fastlane sigh --api_key_path "$JSON_FILE" -a "$PKG" 2>&1)
  echo "$SIGH_OUTPUT"

  PROVISION_FILE=$(find . -maxdepth 1 -name "*${PKG}*.mobileprovision" | head -n 1)
  if [ -z "$PROVISION_FILE" ]; then
    if echo "$SIGH_OUTPUT" | grep -q "Successfully downloaded provisioning profile"; then
      PROVISION_FILE=$(find . -maxdepth 1 -name "*.mobileprovision" -newer "$TMP_MARKER" | head -n 1)
    fi
  fi
  rm -f "$TMP_MARKER"

  if [ -z "$PROVISION_FILE" ]; then
    log_error "No .mobileprovision file found for $PKG"
    FAILED_PACKAGES+=("$PKG")
  else
    ROLLBACK_FILES+=("$(pwd)/$PROVISION_FILE")
    log_success "Profile downloaded for $PKG → $(basename "$PROVISION_FILE")"
    
    if ! $DRY_RUN; then
      PROFILE_NAME=$(security cms -D -i "$PROVISION_FILE" 2>/dev/null \
        | grep -A1 "<key>Name</key>" | grep "<string>" \
        | sed 's/.*<string>\(.*\)<\/string>.*/\1/' | xargs)
        
      if [ -n "$PROFILE_NAME" ]; then
        MATCHED_KEYS+=("$PKG")
        MATCHED_VALUES+=("$PROFILE_NAME")
      else
        log_warn "Could not extract Name from downloaded profile."
      fi
    else
      MATCHED_KEYS+=("$PKG")
      MATCHED_VALUES+=("DRY_RUN_PROFILE_${PKG}")
    fi
  fi
done

if [ ${#FAILED_PACKAGES[@]} -ne 0 ]; then
  log_error "Failed packages:"
  for fp in "${FAILED_PACKAGES[@]}"; do echo -e "   ${RED}• $fp${RESET}"; done
  log_fatal "Step 4 failed. Verify bundle IDs exist in App Store Connect and re-run."
fi

$DRY_RUN || log_success "All ${#PACKAGE_NAMES[@]} provisioning profile(s) downloaded."
show_progress 4 $TOTAL_STEPS "Provisioning profiles downloaded"

# =============================================================================
# STEP 5 — Extract Team ID from cert
# =============================================================================
log_step "STEP 5/${TOTAL_STEPS}: Extracting Team ID from certificate"

TEAMID=""

if $DRY_RUN; then
  log_dry "Would extract Team ID (OU) from $CERTNAME.cer via openssl."
  TEAMID="DRYRUN_TEAM"
else
  OPENSSL_OUT=$(openssl x509 -in "${CERTNAME}.cer" -inform DER -text -noout 2>&1)
  [ $? -ne 0 ] && { log_error "openssl failed:"; echo "$OPENSSL_OUT"; log_fatal "Step 5 failed."; }
  TEAMID=$(echo "$OPENSSL_OUT" | grep "Subject:" | grep -oE 'OU=[A-Z0-9]+' | head -n 1 | cut -d= -f2)
  [ -z "$TEAMID" ] && log_fatal "Could not extract Team ID (OU) from certificate."
  log_success "Team ID: $TEAMID"
fi

show_progress 5 $TOTAL_STEPS "Team ID: $TEAMID"

# =============================================================================
# STEP 6 — Navigate to ios/
# =============================================================================
log_step "STEP 6/${TOTAL_STEPS}: Navigating to ios/"

cd ../.. || log_fatal "Failed to cd back to project root."
[ ! -d "ios" ] && log_fatal "ios/ directory not found in project root."
cd ios    || log_fatal "Failed to cd into ios/"
[ "$(basename "$(pwd)")" != "ios" ] && log_fatal "Expected ios/ but got: $(pwd)"
log_success "Now in: $(pwd)"
show_progress 6 $TOTAL_STEPS "Navigated to ios/"

# =============================================================================
# STEP 7 — Create ExportOptions.plist
# =============================================================================
log_step "STEP 7/${TOTAL_STEPS}: Creating ExportOptions.plist"

PLIST_FILE="ExportOptions.plist"

if $DRY_RUN; then
  log_dry "Would create: ios/ExportOptions.plist"
  log_dry "  teamID: $TEAMID"
  for i in "${!MATCHED_KEYS[@]}"; do
    log_dry "  ${MATCHED_KEYS[$i]} → ${MATCHED_VALUES[$i]}"
  done
else
  cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>${TEAMID}</string>
	<key>provisioningProfiles</key>
	<dict>
EOF
  for i in "${!MATCHED_KEYS[@]}"; do
    echo "		<key>${MATCHED_KEYS[$i]}</key>"    >> "$PLIST_FILE"
    echo "		<string>${MATCHED_VALUES[$i]}</string>" >> "$PLIST_FILE"
  done
  cat >> "$PLIST_FILE" <<'EOF'
	</dict>
	<key>compileBitcode</key>
	<false/>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

  [ ! -f "$PLIST_FILE" ] && log_fatal "Failed to create ExportOptions.plist"

  PLUTIL_OUT=$(plutil -lint "$PLIST_FILE" 2>&1)
  echo "$PLUTIL_OUT" | grep -q "OK" \
    && log_success "ExportOptions.plist is valid — $PLUTIL_OUT" \
    || { log_error "Plist validation failed: $PLUTIL_OUT"; cat "$PLIST_FILE"; log_fatal "Step 8 failed."; }

  ROLLBACK_FILES+=("$(pwd)/$PLIST_FILE")
fi

show_progress 7 $TOTAL_STEPS "ExportOptions.plist created ✓"

# Remove trap — all steps passed, rollback no longer needed
trap - ERR

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
if $DRY_RUN; then
echo -e "${BOLD}${YELLOW}║        DRY-RUN COMPLETE — no changes were made        ║${RESET}"
else
echo -e "${BOLD}${GREEN}║          ALL STEPS COMPLETED SUCCESSFULLY              ║${RESET}"
fi
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e "  ${CYAN}Key ID:${RESET}   $AUTHKEY"
echo -e "  ${CYAN}Team ID:${RESET}  $TEAMID"
echo -e "  ${CYAN}Cert:${RESET}     $CERTNAME"
echo -e "  ${CYAN}Profiles:${RESET}"
for i in "${!MATCHED_KEYS[@]}"; do
  echo -e "    ${YELLOW}$((i+1)). ${MATCHED_KEYS[$i]}${RESET} → ${MATCHED_VALUES[$i]}"
done
echo -e "  ${CYAN}Log:${RESET}      $LOG_FILE"
echo ""

if ! $DRY_RUN; then
  # Navigate back to the project root before executing build commands
  cd "$PROJECT_ROOT" || log_fatal "Failed to return to project root."

  JSON_REL="./fastlane/ios/AuthKey_${AUTHKEY}.json"
  
  echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}                   BUILD & UPLOAD                      ${RESET}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo ""
  
  # =============================================================================
  # STEP 8 — Build IPA
  # =============================================================================
  echo -e "${CYAN}▶ NEXT STEP: Build the iOS App (.ipa)${RESET}"
  echo -e "This step will compile your Flutter app and sign it for the App Store using the profiles we just downloaded."
  echo ""
  
  # Prompt the user for permission to execute
  read -rp "$(echo -e "${BOLD}Do you want to build the IPA now? (y/n): ${RESET}")" RUN_BUILD
  
  if [[ "$RUN_BUILD" == "y" || "$RUN_BUILD" == "Y" ]]; then
    log_info "Starting IPA build... This may take a few minutes."
    
    # Execute the fastlane gym command
    fastlane gym \
      --workspace "${PROJECT_ROOT}/ios/Runner.xcworkspace" \
      --scheme "Runner" \
      --configuration "Release" \
      --clean \
      --export_method "app-store" \
      --export_options "${PROJECT_ROOT}/ios/ExportOptions.plist" \
      --output_directory "${PROJECT_ROOT}/ios/build/ipa"
      
    if [ $? -eq 0 ]; then
      log_success "IPA built successfully! Saved in: ${PROJECT_ROOT}/ios/build/ipa"
    else
      log_error "IPA build failed. Check the errors above."
      exit 1
    fi
  else
    echo -e "${YELLOW}Skipped IPA build.${RESET}"
  fi
  
  echo ""
  
  # =============================================================================
  # STEP 9 — Upload to TestFlight
  # =============================================================================
  echo -e "${CYAN}▶ NEXT STEP: Upload to TestFlight${RESET}"
  echo -e "This step will upload your generated .ipa file to App Store Connect using your API Key."
  echo ""
  
  # Prompt the user for permission to upload
  read -rp "$(echo -e "${BOLD}Do you want to upload to TestFlight now? (y/n): ${RESET}")" RUN_UPLOAD
  
  if [[ "$RUN_UPLOAD" == "y" || "$RUN_UPLOAD" == "Y" ]]; then
    log_info "Starting TestFlight upload... Please wait."
    echo -e "${YELLOW}Note: You will see the upload progress and percentage logs below from Apple's Transporter.${RESET}"
    
    # Execute the fastlane pilot upload command
    fastlane pilot upload \
      --ipa "${PROJECT_ROOT}/ios/build/ipa/Runner.ipa" \
      --api_key_path "${PROJECT_ROOT}/fastlane/ios/AuthKey_${AUTHKEY}.json" \
      --skip_waiting_for_build_processing
      
    if [ $? -eq 0 ]; then
      log_success "Upload complete! Your app is now processing on TestFlight."
      echo -e "${CYAN}You will receive an email from Apple when it is ready to test.${RESET}"
    else
      log_error "Upload failed. Check the errors above."
      exit 1
    fi
  else
    echo -e "${YELLOW}Skipped TestFlight upload.${RESET}"
  fi

  echo ""
  echo -e "${BOLD}${GREEN}🎉 ALL SETUP AND DEPLOYMENT FINISHED! Happy Coding!${RESET}"
fi