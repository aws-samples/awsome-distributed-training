#!/bin/bash

set -exuo pipefail

cat << 'EOF' > /opt/inputrc-osx
# A few bash shortcuts when ssh-ing from OSX
"ƒ": forward-word    # alt-f
"∫": backward-word   # alt-b
"≥": yank-last-arg   # alt-.
"∂": kill-word       # alt-d

";3D": backward-word  # alt-left
";3C": forward-word   # alt-right

"\e[1;3D": backward-word ### Alt left
"\e[1;3C": forward-word ### Alt right
EOF

echo -e "\nbind -f /opt/inputrc-osx" >> /etc/profile.d/z99-initsmhp.sh
