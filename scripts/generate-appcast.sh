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

    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
    local tmpfile
    tmpfile=$(mktemp)

    # Fetch to temp file and sanitize JSON (remove control characters that break jq)
    if ! curl -sS "$api_url" 2>/dev/null | tr -d '\000-\011\013-\037' > "$tmpfile"; then
        log_error "Failed to fetch releases from $api_url"
        rm -f "$tmpfile"
        exit 1
    fi

    # Validate JSON
    if ! jq empty "$tmpfile" 2>/dev/null; then
        log_error "Invalid JSON response from GitHub API"
        rm -f "$tmpfile"
        exit 1
    fi

    cat "$tmpfile"
    rm -f "$tmpfile"
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

    # Convert Markdown to HTML (or escape for plain text if pandoc unavailable)
    local description
    description=$(markdown_to_html "$body")

    cat << EOF
        <item>
            <title>Version ${version}</title>
            <sparkle:version>${version}</sparkle:version>
            <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
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

        # Signature would be read from a signatures file if available
        local signature=""
        local sig_file="${OUTPUT_DIR}/signatures/${tag}.sig"
        if [[ -f "$sig_file" ]]; then
            signature=$(cat "$sig_file")
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
