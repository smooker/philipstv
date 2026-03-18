# philipstv

CLI tool for controlling Philips Smart TVs via the JointSpace HTTP API (v6).

Pure Perl, no heavy dependencies. Direct HTTPS with Digest Authentication.
Fully standalone — including pairing, no Python needed.

## Requirements

- Perl 5
- `LWP::UserAgent` (libwww-perl)
- `JSON`
- `IO::Socket::SSL`
- `LWP::Authen::Digest`
- `Digest::HMAC_SHA1`
- `MIME::Base64` (core)

On Gentoo: `emerge dev-perl/libwww-perl dev-perl/JSON dev-perl/IO-Socket-SSL dev-perl/Digest-HMAC`

## Pairing

First-time setup — pair with your TV:

```bash
./philipstv.pl --host 192.168.1.100 pair
```

The TV will display a PIN code. Enter it, and you'll receive credentials
(username + password). Save them to `~/.philipstv.conf`:

```ini
host = 192.168.1.100
user = your_username_here
pass = your_password_here
```

## Usage

```bash
# Status
./philipstv.pl status
./philipstv.pl system

# Volume
./philipstv.pl vol              # show current
./philipstv.pl vol 20           # set to 20
./philipstv.pl vol+ 5           # up by 5
./philipstv.pl vol-             # down by 3 (default)
./philipstv.pl mute
./philipstv.pl unmute

# Channels
./philipstv.pl channels         # list all
./philipstv.pl ch               # show current
./philipstv.pl ch "BBC One"     # switch by name
./philipstv.pl ch nova          # partial match

# Remote keys
./philipstv.pl key Standby
./philipstv.pl key VolumeUp
./philipstv.pl key Home
./philipstv.pl key CursorUp
./philipstv.pl key Confirm

# Settings
./philipstv.pl settings         # show settings tree with node IDs
./philipstv.pl setting-get 123  # get value by node ID
./philipstv.pl setting-set 123 '{"value": 1}'

# Raw API access
./philipstv.pl get audio/volume
./philipstv.pl post input/key '{"key":"Confirm"}'
```

## Options

```
--host IP        TV IP address (or set in ~/.philipstv.conf)
--port PORT      API port (default: 1926)
--user USER      Digest auth username (from pairing)
--pass PASS      Digest auth password (from pairing)
--debug          Show HTTP requests
```

## Tested on

| Model | Resolution | API | OS |
|-------|-----------|-----|-----|
| Philips 43PUS7810/12 | 4K UHD | v6.1.0 | Linux |

Should work with other Philips Android/Linux TVs that support JointSpace API v6.

## License

GPL-3.0 — see [LICENSE](LICENSE)
