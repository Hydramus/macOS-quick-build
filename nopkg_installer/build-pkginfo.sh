#!/bin/bash
# Generates nopkg-enroll.pkginfo from the template + enrollment.sh.
# The setup scripts are embedded as a base64 tar.gz of the committed repo
# (git archive HEAD), so the Mac downloads nothing from GitHub at run time.
# Commit your changes, then run this, then upload the pkginfo to SimpleMDM.
# Requires Python 3 (pre-installed on macOS 12+).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${SCRIPT_DIR}/nopkg-enroll.pkginfo.template"
ENROLLMENT="${SCRIPT_DIR}/enrollment.sh"
OUTPUT="${SCRIPT_DIR}/nopkg-enroll.pkginfo"
PAYLOAD_PATHS=(macOSMachineSetup.sh setup-system.sh setup-user.sh autobrew.sh rosetta-2-install.sh lib configfiles)

if [[ ! -f "$ENROLLMENT" ]]; then
    echo "ERROR: enrollment.sh not found at $ENROLLMENT" >&2
    exit 1
fi

# The payload is what is committed, so refuse to build from uncommitted edits
if ! git -C "$REPO_DIR" diff --quiet HEAD -- "${PAYLOAD_PATHS[@]}" nopkg_installer/enrollment.sh; then
    echo "ERROR: commit your changes first; the payload is built from HEAD" >&2
    exit 1
fi

PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT
git -C "$REPO_DIR" archive --format=tar.gz HEAD -- "${PAYLOAD_PATHS[@]}" | base64 | tr -d '\n' > "$PAYLOAD_FILE"
COMMIT=$(git -C "$REPO_DIR" rev-parse --short HEAD)

python3 - "$TEMPLATE" "$ENROLLMENT" "$OUTPUT" "$PAYLOAD_FILE" "$COMMIT" << 'EOF'
import sys
import xml.sax.saxutils as sax

template_path, script_path, output_path, payload_path, commit = sys.argv[1:6]

with open(script_path) as f:
    script_content = f.read()
with open(payload_path) as f:
    payload = f.read().strip()

if script_content.count('__PAYLOAD__') != 1 or len(payload) < 100:
    print("ERROR: payload placeholder or payload missing", file=sys.stderr)
    sys.exit(1)
script_content = script_content.replace('__PAYLOAD__', payload)
script_content = script_content.replace('\nset -euo pipefail\n', f'\n# Payload: commit {commit}\nset -euo pipefail\n', 1)

escaped = sax.escape(script_content)

with open(template_path) as f:
    template = f.read()

if '__POSTINSTALL_SCRIPT__' not in template:
    print("ERROR: placeholder __POSTINSTALL_SCRIPT__ not found in template", file=sys.stderr)
    sys.exit(1)

output = template.replace('__POSTINSTALL_SCRIPT__', escaped)

with open(output_path, 'w', newline='\n') as f:
    f.write(output)

print(f"Generated: {output_path} (payload from commit {commit}, {len(payload)} base64 characters)")
EOF
