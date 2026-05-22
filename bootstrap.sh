#!/bin/sh
# Install Perl deps into ./local/ — no system or ~/perl5 pollution.
# Re-run safely; only fetches what's missing.
set -e
cd "$(dirname "$0")"

CPANM=./cpanm
if [ ! -x "$CPANM" ]; then
    curl -sL https://cpanmin.us -o "$CPANM"
    chmod +x "$CPANM"
fi

exec perl "$CPANM" -L local --notest \
    --mirror https://cpan.metacpan.org/ --mirror-only \
    JSON LWP::UserAgent Digest::HMAC_SHA1
