#!/bin/bash
# Generates nopkg-enroll.pkginfo from the template + enrollment.sh.
# Run this whenever enrollment.sh changes before uploading to SimpleMDM.
# Requires Python 3 (pre-installed on macOS 12+).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/nopkg-enroll.pkginfo.template"
ENROLLMENT="${SCRIPT_DIR}/enrollment.sh"
OUTPUT="${SCRIPT_DIR}/nopkg-enroll.pkginfo"

if [[ ! -f "$ENROLLMENT" ]]; then
    echo "ERROR: enrollment.sh not found at $ENROLLMENT" >&2
    exit 1
fi

python3 - "$TEMPLATE" "$ENROLLMENT" "$OUTPUT" << 'EOF'
import sys
import xml.sax.saxutils as sax

template_path, script_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(script_path) as f:
    script_content = f.read()

escaped = sax.escape(script_content)

with open(template_path) as f:
    template = f.read()

if '__POSTINSTALL_SCRIPT__' not in template:
    print("ERROR: placeholder __POSTINSTALL_SCRIPT__ not found in template", file=sys.stderr)
    sys.exit(1)

output = template.replace('__POSTINSTALL_SCRIPT__', escaped)

with open(output_path, 'w') as f:
    f.write(output)

print(f"Generated: {output_path}")
EOF
