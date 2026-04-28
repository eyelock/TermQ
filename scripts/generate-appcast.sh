#!/bin/bash
# Generate Sparkle appcast.xml files from GitHub Releases
# Usage: ./scripts/generate-appcast.sh [--sign]

set -euo pipefail

REPO_OWNER="eyelock"
REPO_NAME="TermQ"
OUTPUT_DIR="Docs"
MIN_SYSTEM_VERSION="14.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Check for required tools
check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: brew install ${missing[*]}"
        exit 1
    fi

    # Check for pandoc (optional, for Markdown to HTML conversion)
    if ! command -v pandoc &> /dev/null; then
        log_warn "pandoc not found - release notes will display as plain Markdown"
        log_info "For better formatting, install with: brew install pandoc"
    fi
}

# Fetch releases from GitHub API
fetch_releases() {
    log_info "Fetching releases from GitHub..."

    local base_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
    local all_releases="[]"
    local page=1

    # Use GH_TOKEN if available — authenticated requests bypass the API cache so a
    # freshly published release is visible without waiting for cache expiry
    local auth_header=()
    if [ -n "${GH_TOKEN:-}" ]; then
        auth_header=(-H "Authorization: Bearer $GH_TOKEN")
    fi

    while true; do
        local tmpfile
        tmpfile=$(mktemp)
        local url="${base_url}?per_page=100&page=${page}"

        if ! curl -sS "${auth_header[@]}" "$url" 2>/dev/null | tr -d '\000-\011\013-\037' > "$tmpfile"; then
            log_error "Failed to fetch releases page $page"
            rm -f "$tmpfile"
            exit 1
        fi

        if ! jq empty "$tmpfile" 2>/dev/null; then
            log_error "Invalid JSON from GitHub API (page $page)"
            rm -f "$tmpfile"
            exit 1
        fi

        local count
        count=$(jq 'length' "$tmpfile")

        if [[ "$count" -eq 0 ]]; then
            rm -f "$tmpfile"
            break
        fi

        local page_data
        page_data=$(cat "$tmpfile")
        rm -f "$tmpfile"

        all_releases=$(printf '%s\n%s' "$all_releases" "$page_data" | jq -s 'add')

        [[ "$count" -lt 100 ]] && break
        page=$((page + 1))
    done

    log_info "Found $(echo "$all_releases" | jq 'length') release(s)"
    echo "$all_releases"
}

# Convert GitHub release date to RFC 2822 format
format_date() {
    local iso_date="$1"
    # Detect OS and use appropriate date command
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date command
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" "+%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null || echo "$iso_date"
    else
        # Linux date command
        date -d "$iso_date" "+%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null || echo "$iso_date"
    fi
}

# Extract version from tag (removes 'v' prefix)
extract_version() {
    local tag="$1"
    echo "${tag#v}"
}

# Convert tag version to Sparkle-safe format.
# SUStandardVersionComparator truncates at the first dash, so "0.7.0-beta.8"
# and "0.7.0-beta.9" both reduce to "0.7.0" and compare as equal.
# The dot-notation form is correctly ordered by Sparkle's comparator.
#   0.7.0-beta.9  → 0.7.0.b9
#   0.7.0-alpha.3 → 0.7.0.a3
#   0.7.0-rc.2    → 0.7.0.rc2
#   0.7.0         → 0.7.0 (no change for stable)
sparkle_version() {
    local version="$1"
    echo "$version" | sed 's/-beta\./.b/;s/-alpha\./.a/;s/-rc\./.rc/'
}

# Check if release is a pre-release (beta, alpha, rc)
is_prerelease() {
    local tag="$1"
    local is_github_prerelease="$2"

    if [[ "$is_github_prerelease" == "true" ]]; then
        echo "true"
        return
    fi

    if [[ "$tag" =~ (alpha|beta|rc|dev) ]]; then
        echo "true"
        return
    fi

    echo "false"
}

# Convert Markdown to HTML if pandoc is available
markdown_to_html() {
    local markdown="$1"

    if command -v pandoc &> /dev/null; then
        # Use pandoc to convert Markdown to HTML
        # --from=gfm: GitHub-flavored Markdown
        # --to=html: Convert to HTML
        # --wrap=none: Don't wrap lines
        echo "$markdown" | pandoc --from=gfm --to=html --wrap=none 2>/dev/null || echo "$markdown"
    else
        # Fallback: escape HTML entities for plain text display
        echo "$markdown" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
    fi
}

# Generate XML for a single release item
generate_item() {
    local tag="$1"
    local title="$2"
    local pub_date="$3"
    local body="$4"
    local download_url="$5"
    local file_size="$6"
    local signature="${7:-}"

    local version
    version=$(extract_version "$tag")
    local sparkle_ver
    sparkle_ver=$(sparkle_version "$version")

    # Convert Markdown to HTML (or escape for plain text if pandoc unavailable)
    local description
    description=$(markdown_to_html "$body")

    cat << EOF
        <item>
            <title>Version ${sparkle_ver}</title>
            <sparkle:version>${sparkle_ver}</sparkle:version>
            <sparkle:shortVersionString>${sparkle_ver}</sparkle:shortVersionString>
            <pubDate>${pub_date}</pubDate>
            <description><![CDATA[${description}]]></description>
            <enclosure
                url="${download_url}"
                ${signature:+sparkle:edSignature=\"${signature}\"}
                length="${file_size}"
                type="application/octet-stream"/>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
        </item>
EOF
}

# Generate appcast XML file
generate_appcast() {
    local releases="$1"
    local include_prereleases="$2"
    local output_file="$3"

    log_info "Generating ${output_file}..."

    local items=""
    local count=0

    # Use temp file to avoid process substitution issues with pipes in CI
    # Process substitution can cause "Broken pipe" errors when the while loop exits early
    local releases_file
    releases_file=$(mktemp)
    echo "$releases" | jq -c '.[]' > "$releases_file"

    # Process each release
    while IFS= read -r release; do
        local tag
        tag=$(echo "$release" | jq -r '.tag_name')

        [[ "$tag" == "null" || -z "$tag" ]] && continue

        local is_github_prerelease
        is_github_prerelease=$(echo "$release" | jq -r '.prerelease')

        local prerelease
        prerelease=$(is_prerelease "$tag" "$is_github_prerelease")

        # Skip prereleases for stable feed
        if [[ "$include_prereleases" == "false" && "$prerelease" == "true" ]]; then
            continue
        fi

        local title
        title=$(echo "$release" | jq -r '.name // .tag_name')

        local pub_date_iso
        pub_date_iso=$(echo "$release" | jq -r '.published_at')
        local pub_date
        pub_date=$(format_date "$pub_date_iso")

        local body
        body=$(echo "$release" | jq -r '.body // ""')

        # Find the zip asset (Sparkle prefers zip)
        local download_url
        local file_size
        download_url=$(echo "$release" | jq -r '[.assets[] | select(.name | endswith(".zip"))][0].browser_download_url // empty')
        file_size=$(echo "$release" | jq -r '[.assets[] | select(.name | endswith(".zip"))][0].size // 0')

        if [[ -z "$download_url" || "$download_url" == "null" ]]; then
            log_warn "No zip asset found for release $tag, skipping..."
            continue
        fi

        # Fetch EdDSA signature from the .zip.sig release asset
        local signature=""
        local sig_url
        sig_url=$(echo "$release" | jq -r '[.assets[] | select(.name | endswith(".zip.sig"))][0].browser_download_url // empty')
        if [[ -n "$sig_url" && "$sig_url" != "null" ]]; then
            # -L is required: GitHub release asset URLs return a 302 redirect to CDN (content-length: 0)
            signature=$(curl -sSL "$sig_url" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$signature" ]]; then
                log_info "Found EdDSA signature for $tag"
            else
                log_error "Downloaded .zip.sig for $tag but got empty content — aborting to prevent shipping unsigned update"
                exit 1
            fi
        fi
        if [[ -z "$signature" ]]; then
            log_warn "No EdDSA signature found for $tag — Sparkle update validation will fail"
        fi

        items+=$(generate_item "$tag" "$title" "$pub_date" "$body" "$download_url" "$file_size" "$signature")
        items+=$'\n'

        count=$((count + 1))
    done < "$releases_file"

    # Cleanup temp file
    rm -f "$releases_file"

    # Generate the full appcast XML
    cat > "${OUTPUT_DIR}/${output_file}" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>TermQ Updates</title>
        <link>https://github.com/${REPO_OWNER}/${REPO_NAME}</link>
        <description>Most recent updates to TermQ</description>
        <language>en</language>
${items}
    </channel>
</rss>
EOF

    log_info "Generated ${output_file} with ${count} release(s)"
}

# Main execution
main() {
    log_info "TermQ Appcast Generator"
    log_info "======================"

    check_dependencies

    # Create output directory if needed
    mkdir -p "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}/signatures"

    # Fetch releases
    local releases
    releases=$(fetch_releases)

    # Check if we got any releases
    local release_count
    release_count=$(echo "$releases" | jq 'length')

    if [[ "$release_count" -eq 0 ]]; then
        log_warn "No releases found. Creating empty appcast files."
    fi

    log_info "Found ${release_count} release(s)"

    # Generate stable appcast (excludes pre-releases)
    generate_appcast "$releases" "false" "appcast.xml"

    # Generate beta appcast (includes all releases)
    generate_appcast "$releases" "true" "appcast-beta.xml"

    log_info "Done! Appcast files generated in ${OUTPUT_DIR}/"
}

main "$@"
