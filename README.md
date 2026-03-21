# philipstv

CLI tool for controlling Philips Smart TVs via the JointSpace HTTP API (v6).

Pure Perl, zero external runtime dependencies. Single file — includes
TV control, DLNA media casting with built-in HTTP server, Wake on LAN,
and tmux-based TV dashboard. No Python, no Node.js, no Java.

## Features

- **TV Control** — volume, channels, input source, remote keys, settings
- **DLNA Cast** — play local files/URLs on TV (built-in Perl HTTP server, fork-per-request)
- **NVENC Transcode** — hardware video encoding with NVIDIA RTX GPU
- **Wake on LAN** — power on TV from CLI (works over WiFi on supported models)
- **TV Dashboard** — tmux session with playlist, remote control aliases, HTTP server log
- **Virtual X Screen** — Xephyr virtual display → ffmpeg NVENC capture → DLNA → TV as wireless monitor *(xorg branch)*
- **Pairing** — interactive, fully standalone (no external tools)

## Requirements

- Perl 5
- `LWP::UserAgent` (libwww-perl)
- `JSON`
- `IO::Socket::SSL`
- `Digest::HMAC_SHA1`
- `MIME::Base64` (core)
- `IO::Socket::INET` (core)

On Gentoo: `emerge dev-perl/libwww-perl dev-perl/JSON dev-perl/IO-Socket-SSL dev-perl/Digest-HMAC`

Optional: `ffmpeg` with NVENC support (for `--nvenc cast` and `tv-screen`)

## Quick Start

```bash
# Pair with TV (one-time)
./philipstv.pl --host 192.168.1.100 pair

# Control
./philipstv.pl status
./philipstv.pl vol+ 5
./philipstv.pl ch nova

# Play video on TV
./philipstv.pl dlna-play movie.mkv

# Wake TV + play
./philipstv.pl on
./philipstv.pl dlna-play ~/Videos/movie.mp4

# TV Dashboard (tmux)
./philipstv.pl tv ~/Videos/
```

## Usage

```bash
# Status
./philipstv.pl status             # volume, channel, screen state
./philipstv.pl system             # model, firmware, API version

# Volume
./philipstv.pl vol                # show current
./philipstv.pl vol 20             # set to 20
./philipstv.pl vol+ 5             # up by 5
./philipstv.pl vol-               # down by 3 (default)
./philipstv.pl mute / unmute

# Channels
./philipstv.pl channels           # list all
./philipstv.pl ch                 # show current
./philipstv.pl ch nova            # switch by name (partial match)

# Remote keys
./philipstv.pl key Standby
./philipstv.pl key Home / Back / Confirm
./philipstv.pl key CursorUp / CursorDown / CursorLeft / CursorRight
./philipstv.pl key Subtitle       # switch subtitle track

# DLNA Cast — built-in Perl HTTP server
./philipstv.pl dlna-play video.mp4           # serve local file + play on TV
./philipstv.pl dlna-play movie.mkv           # MKV with subtitles
./philipstv.pl dlna-play http://url/vid.mp4  # play remote URL
./philipstv.pl --nvenc cast video.mkv        # transcode with RTX GPU + play
./philipstv.pl dlna-status                   # DLNA transport state
./philipstv.pl stop-cast                     # stop playback

# Wake on LAN
./philipstv.pl on                 # wake TV (WoL magic packet)

# TV Dashboard — tmux session
./philipstv.pl tv ~/Videos/       # folder mode: playlist + remote
./philipstv.pl tv video.mp4       # play file + open dashboard
# tmux windows: http | playlist | remote
# remote has aliases: vol+ vol- mute pause play stop dlna-play status
# arrow-up in remote shows all available commands

# Virtual X Screen (xorg branch)
./philipstv.pl tv-screen          # Xephyr :1 → ffmpeg NVENC → DLNA → TV
./philipstv.pl tv-screen 1920x1080
DISPLAY=:1 firefox &              # run apps on virtual TV display
./philipstv.pl tv-screen-stop

# Quick reference
./philipstv.pl helptv

# Settings
./philipstv.pl settings           # show settings tree with node IDs
./philipstv.pl setting-get 123    # get value
./philipstv.pl setting-set 123 '{"value": 1}'

# Raw API access
./philipstv.pl get audio/volume
./philipstv.pl post input/key '{"key":"Confirm"}'
```

## Options

```
--host IP        TV IP address (or set in config)
--port PORT      API port (default: 1926)
--user USER      Digest auth username (from pairing)
--pass PASS      Digest auth password (from pairing)
--nvenc          Use NVIDIA NVENC for hardware video encoding
--cast-port N    HTTP server port for casting (default: 8888)
--debug          Show HTTP requests and DLNA SOAP details
```

## Configuration

`~/.philipstv.conf`:
```ini
host = 192.168.1.100
user = your_username_here
pass = your_password_here
mac = aa:bb:cc:dd:ee:ff    # for Wake on LAN
```

## Subtitle Workaround

Philips DLNA player may crash when switching subtitle tracks during playback.
Workaround: remux with preferred subtitles as first (default) track:

```bash
ffmpeg -i input.mkv -map 0:v -map 0:a -map 0:s:1 -map 0:s:0 \
  -c copy -disposition:s:0 default -disposition:s:1 0 output.mkv
```

## Tested on

| Model | Display | API | OS | DLNA | WoL WiFi |
|-------|---------|-----|----|------|----------|
| Philips 43PUS7810/12 | 4K UHD 43" | v6.1.0 | TitanOS/Linux | DMR-1.50 | Yes |

Should work with other Philips Android/Linux/TitanOS TVs supporting JointSpace API v6.

## License

GPL-3.0 — see [LICENSE](LICENSE)
