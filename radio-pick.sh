#!/bin/sh
# Pick an Icecast stream from ice.smooker.org with fzf, then act on selection.
# Default action: print URL. Override with $ACTION="mpv" or pipe to philipstv.pl.
set -e

ICE_URL="http://ice.smooker.org"
ICE_AUTH="radio:motorola"

sel=$(
    curl -fsSL -u "$ICE_AUTH" "$ICE_URL/status-json.xsl" \
      | jq -r '
          .icestats.source
          | (if type=="array" then . else [.] end)
          | .[]
          | "\(.server_name // .server_description // .listenurl)\t\(.listenurl)"
        ' \
      | fzf --with-nth=1 --delimiter='\t' --prompt='radio> '
)
[ -n "$sel" ] || exit 1

url=$(printf '%s' "$sel" | cut -f2)
echo "$url"

case "${ACTION:-print}" in
    print) ;;
    mpv)   exec mpv --no-video "$url" ;;
    tv)    exec "$(dirname "$0")/philipstv.pl" dlna-play "$url" ;;
    *)     exec $ACTION "$url" ;;
esac
