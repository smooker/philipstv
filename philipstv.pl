#!/usr/bin/perl
# philipstv.pl — Philips TV CLI control via JointSpace API v6
# Copyright (C) 2026 smooker <smooker@smooker.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# https://github.com/smooker/philipstv

use strict;
use warnings;
use Getopt::Long;
use JSON;
use LWP::UserAgent;
use HTTP::Request;
use MIME::Base64;
use Digest::HMAC_SHA1;
use Sys::Hostname;
use Socket qw(inet_aton sockaddr_in);
use IO::Socket::INET;

my $HOST     = '';
my $PORT     = 1926;
my $API      = 6;
my $USER     = '';
my $PASS     = '';
my $CONF     = '';
my $MAC      = '';
my $DEBUG    = 0;
my $HELP     = 0;
my $NVENC    = 0;
my $CAST_PORT = 8888;

GetOptions(
    'host=s'   => \$HOST,
    'port=i'   => \$PORT,
    'api=i'    => \$API,
    'user=s'   => \$USER,
    'pass=s'   => \$PASS,
    'conf=s'   => \$CONF,
    'debug'    => \$DEBUG,
    'help'     => \$HELP,
    'nvenc'    => \$NVENC,
    'cast-port=i' => \$CAST_PORT,
) or die "Bad options. Try --help\n";

my $CMD  = shift @ARGV || '';
my @ARGS = @ARGV;

if ($HELP || !$CMD) {
    print_help();
    exit 0;
}

# Load config file: --conf, or ~/.philipstv.conf, or /home/claude-agent/.philipstv.conf
my $CONFFILE = $CONF;
unless ($CONFFILE && -f $CONFFILE) {
    my $home = $ENV{HOME} || (getpwuid($<))[7] || '';
    my @candidates = (
        ($home ? "$home/.philipstv.conf" : ()),
        '/home/claude-agent/.philipstv.conf',
    );
    for my $c (@candidates) {
        if (-f $c) { $CONFFILE = $c; last; }
    }
}
if ($CONFFILE && -f $CONFFILE) {
    print STDERR "Config: $CONFFILE\n" if $DEBUG;
    open(my $fh, '<', $CONFFILE);
    while (<$fh>) {
        chomp;
        next if /^\s*#/ || /^\s*$/;
        if (/^(\w+)\s*=\s*(.+)/) {
            my ($k, $v) = ($1, $2);
            $v =~ s/\s+$//;
            $HOST ||= $v if $k eq 'host';
            $PORT ||= $v if $k eq 'port';
            $USER ||= $v if $k eq 'user';
            $PASS ||= $v if $k eq 'pass';
            $MAC  ||= $v if $k eq 'mac';
        }
    }
    close($fh);
}

die "Error: --host is required (or set host in ~/.philipstv.conf)\n" unless $HOST;
if ($CMD ne 'pair') {
    die "Error: --user and --pass required (or run 'pair' first)\n" unless $USER && $PASS;
}

my $BASE = "https://$HOST:$PORT/$API";
my $BASE_HTTP = "http://$HOST:1925/$API";
my $json = JSON->new->utf8->pretty;

# Shared key for HMAC signature during pairing (from Philips JointSpace)
my $AUTH_SHARED_KEY = decode_base64(
    "ZmVay1EQVFOaZhwQ4Kv81ypLAZNczV9sG4KkseXWn1NEk6cXmPKO/MCa9sryslvLCFMnNe4Z4CPXzToowvhHvA=="
);

my $ua = LWP::UserAgent->new(
    ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
    timeout  => 10,
);
$ua->credentials("$HOST:$PORT", 'XTV', $USER, $PASS);

# --- Commands ---

my %commands = (
    'status'      => \&cmd_status,
    'vol'         => \&cmd_vol,
    'vol+'        => \&cmd_vol_up,
    'vol-'        => \&cmd_vol_down,
    'mute'        => \&cmd_mute,
    'unmute'      => \&cmd_unmute,
    'ch'          => \&cmd_channel,
    'channels'    => \&cmd_channels,
    'source'      => \&cmd_source,
    'sources'     => \&cmd_sources,
    'key'         => \&cmd_key,
    'pair'        => \&cmd_pair,
    'hdmi'        => \&cmd_hdmi,
    'get'         => \&cmd_get,
    'post'        => \&cmd_post,
    'screen'      => \&cmd_screen,
    'system'      => \&cmd_system,
    'settings'    => \&cmd_settings,
    'setting-get' => \&cmd_setting_get,
    'setting-set' => \&cmd_setting_set,
    'cast'        => \&cmd_cast,
    'stop-cast'   => \&cmd_stop_cast,
    'dlna-status' => \&cmd_dlna_status,
    'dlna-play'   => \&cmd_dlna_play_url,
    'tv'          => \&cmd_tv,
    'wol'         => \&cmd_wol,
    'on'          => \&cmd_wol,
    'helptv'      => \&cmd_helptv,
    'tv-screen'   => \&cmd_tv_screen,
    'tv-screen-stop' => \&cmd_tv_screen_stop,
);

if (my $fn = $commands{$CMD}) {
    $fn->(@ARGS);
} else {
    die "Unknown command: $CMD\nTry: philipstv.pl --help\n";
}

# --- HTTP helpers ---

sub api_get {
    my ($path) = @_;
    my $url = "$BASE/$path";
    print STDERR "GET $url\n" if $DEBUG;
    my $res = $ua->get($url);
    if (!$res->is_success) {
        print STDERR "GET $path: " . $res->status_line . "\n" if $DEBUG;
        return undef;
    }
    return decode_json($res->content);
}

sub api_post {
    my ($path, $data) = @_;
    my $url = "$BASE/$path";
    my $body = encode_json($data);
    print STDERR "POST $url $body\n" if $DEBUG;
    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'application/json');
    $req->content($body);
    my $res = $ua->request($req);
    print STDERR "POST $path: " . $res->status_line . "\n" if $DEBUG;
    return $res->is_success;
}

# --- Command implementations ---

sub cmd_status {
    my $vol = api_get('audio/volume');
    my $ctx = api_get('context');
    my $act = api_get('activities/tv');
    my $scr = api_get('screenstate');

    print "=== Philips TV $HOST ===\n";
    if ($vol) {
        printf "Volume: %d/%d%s\n", $vol->{current}, $vol->{max},
            $vol->{muted} ? ' (MUTED)' : '';
    }
    if ($ctx) {
        printf "Context: %s\n", $ctx->{level1} || '-';
    }
    if ($act && $act->{channel} && $act->{channel}{ccid}) {
        my $chname = get_channel_name($act->{channel}{ccid}) || $act->{channel}{ccid};
        printf "Channel: %s\n", $chname;
    }
    if ($scr) {
        printf "Screen: %s\n", $scr->{screenstate} || '-';
    }
}

sub cmd_vol {
    my ($level) = @_;
    if (defined $level) {
        $level = int($level);
        api_post('audio/volume', { current => $level, muted => JSON::false });
        print "Volume set to $level\n";
    } else {
        my $vol = api_get('audio/volume');
        if ($vol) {
            printf "Volume: %d/%d%s\n", $vol->{current}, $vol->{max},
                $vol->{muted} ? ' (MUTED)' : '';
        }
    }
}

sub cmd_vol_up {
    my ($step) = @_;
    $step = $step || 3;
    my $vol = api_get('audio/volume') or die "Cannot get volume\n";
    my $new = $vol->{current} + $step;
    $new = $vol->{max} if $new > $vol->{max};
    api_post('audio/volume', { current => $new, muted => JSON::false });
    printf "Volume: %d -> %d\n", $vol->{current}, $new;
}

sub cmd_vol_down {
    my ($step) = @_;
    $step = $step || 3;
    my $vol = api_get('audio/volume') or die "Cannot get volume\n";
    my $new = $vol->{current} - $step;
    $new = $vol->{min} if $new < $vol->{min};
    api_post('audio/volume', { current => $new, muted => JSON::false });
    printf "Volume: %d -> %d\n", $vol->{current}, $new;
}

sub cmd_mute {
    api_post('audio/volume', { muted => JSON::true });
    print "Muted\n";
}

sub cmd_unmute {
    api_post('audio/volume', { muted => JSON::false });
    print "Unmuted\n";
}

sub cmd_channels {
    my $db = api_get('channeldb/tv');
    return unless $db;
    for my $list (@{$db->{channelLists} || []}) {
        my $id = $list->{id};
        my $data = api_get("channeldb/tv/channelLists/$id");
        next unless $data && $data->{Channel};
        printf "%-6s %-30s %s\n", "CCID", "NAME", "PRESET";
        printf "%s\n", "-" x 50;
        for my $ch (@{$data->{Channel}}) {
            printf "%-6s %-30s %s\n",
                $ch->{ccid} || '-',
                $ch->{name} || '-',
                $ch->{preset} || '-';
        }
    }
}

sub cmd_channel {
    my ($name_or_ccid) = @_;
    if (!$name_or_ccid) {
        my $act = api_get('activities/tv');
        if ($act && $act->{channel}) {
            my $name = get_channel_name($act->{channel}{ccid});
            printf "Current: %s (ccid=%s)\n", $name || '?', $act->{channel}{ccid};
        }
        return;
    }
    # Find channel by name or ccid
    my $ccid = find_channel($name_or_ccid);
    if (!$ccid) {
        die "Channel not found: $name_or_ccid\n";
    }
    api_post('activities/tv', { channel => { ccid => $ccid } });
    my $name = get_channel_name($ccid) || $ccid;
    print "Switched to: $name\n";
}

sub cmd_sources {
    my $data = api_get('sources');
    return unless $data;
    for my $src (values %$data) {
        printf "%-6s %s\n", $src->{id} || '-', $src->{name} || '-';
    }
}

sub cmd_source {
    my ($id) = @_;
    if (!$id) {
        my $act = api_get('activities/current');
        print $json->encode($act) if $act;
        return;
    }
    api_post('sources/current', { id => int($id) });
    print "Source set to $id\n";
}

sub cmd_key {
    my ($key) = @_;
    die "Usage: philipstv.pl key <KeyName>\nKeys: Standby, VolumeUp, VolumeDown, Mute, CursorUp, CursorDown, CursorLeft, CursorRight, Confirm, Back, Home, Options, Digit0-9, Play, Pause, Stop, ...\n"
        unless $key;
    api_post('input/key', { key => $key });
    print "Sent key: $key\n";
}

sub cmd_get {
    my ($path) = @_;
    die "Usage: philipstv.pl get <api/path>\n" unless $path;
    my $data = api_get($path);
    print $json->encode($data) if $data;
}

sub cmd_post {
    my ($path, $data_str) = @_;
    die "Usage: philipstv.pl post <api/path> '<json>'\n" unless $path && $data_str;
    my $data = decode_json($data_str);
    my $ok = api_post($path, $data);
    print $ok ? "OK\n" : "FAILED\n";
}

sub cmd_screen {
    my ($state) = @_;
    if ($state) {
        api_post('screenstate', { screenstate => $state });
        print "Screen: $state\n";
    } else {
        my $scr = api_get('screenstate');
        printf "Screen: %s\n", $scr->{screenstate} if $scr;
    }
}

sub cmd_system {
    my $sys = api_get('system');
    return unless $sys;
    printf "Model:    %s (%s)\n", $sys->{name} || '-', $sys->{model} || '-';
    printf "Serial:   %s\n", $sys->{serialnumber} || '-';
    printf "Software: %s\n", $sys->{softwareversion} || '-';
    printf "Country:  %s\n", $sys->{country} || '-';
    printf "Language: %s\n", $sys->{menulanguage} || '-';
    printf "API:      %d.%d.%d\n",
        $sys->{api_version}{Major} || 0,
        $sys->{api_version}{Minor} || 0,
        $sys->{api_version}{Patch} || 0;
    printf "OS:       %s\n", $sys->{featuring}{systemfeatures}{os_type} || '-';
    printf "TV Type:  %s\n", $sys->{featuring}{systemfeatures}{tvtype} || '-';
}

sub cmd_settings {
    my $data = api_get('menuitems/settings/structure');
    return unless $data;
    print_settings_tree($data, 0);
}

sub cmd_setting_get {
    my ($node_id) = @_;
    die "Usage: philipstv.pl setting-get <node_id>\n" unless defined $node_id;
    my $data = api_post_get('menuitems/settings/current', {
        nodes => [{ nodeid => int($node_id) }]
    });
    print $json->encode($data) if $data;
}

sub cmd_setting_set {
    my ($node_id, $value_json) = @_;
    die "Usage: philipstv.pl setting-set <node_id> '<json_value>'\n"
        unless defined $node_id && defined $value_json;
    my $val = decode_json($value_json);
    my $ok = api_post('menuitems/settings/update', {
        values => [{ value => { Nodeid => int($node_id), data => $val } }]
    });
    print $ok ? "OK\n" : "FAILED\n";
}

sub cmd_hdmi {
    my ($num) = @_;
    $num = 1 unless defined $num;

    # Source menu position for HDMI inputs — configurable in .philipstv.conf
    # Default: HDMI-1 = position 5 from top (Home is position 1)
    my $pos = $num;
    if ($CONFFILE && -f $CONFFILE) {
        open my $fh, '<', $CONFFILE;
        while (<$fh>) {
            chomp;
            if (/^hdmi${num}_pos\s*=\s*(\d+)/) {
                $pos = $1;
                last;
            }
        }
        close $fh;
    }

    # Fallback: read from config or use default mapping
    unless ($pos > 1) {
        $pos = 5;  # default for HDMI-1
    }

    my $steps = $pos - 1;  # Home is position 1

    print "Switching to HDMI-$num (source menu position $pos)...\n";

    # Send Source key and wait for menu to open
    api_post('input/key', { key => 'Source' });
    _delay(1.5);

    # Navigate down to the right position
    for my $i (1..$steps) {
        api_post('input/key', { key => 'CursorDown' });
        _delay(0.6);
    }

    # Confirm
    api_post('input/key', { key => 'Confirm' });
    print "Done\n";
}

sub _delay {
    my ($sec) = @_;
    select(undef, undef, undef, $sec);
}

sub cmd_cast {
    my ($file) = @_;
    die "Usage: philipstv.pl [--nvenc] [--cast-port 8888] cast <file|url>\n" unless $file;

    my $use_nvenc = $NVENC;
    my $http_port = $CAST_PORT;

    # Get local IP (same network as TV)
    my $local_ip = _get_local_ip();
    die "Cannot determine local IP\n" unless $local_ip;

    # Build ffmpeg command
    my $vcodec = $use_nvenc ? 'h264_nvenc -preset p4 -b:v 8M' : 'libx264 -preset fast -crf 23';
    # Transcode to temp file, serve via HTTP
    my $tmpdir = "/tmp/philipstv-cast";
    system("mkdir -p $tmpdir");
    my $outfile = "$tmpdir/stream.mp4";

    my @ffcmd = (
        'ffmpeg', '-y',
        '-i', $file,
        '-c:v', split(' ', $vcodec),
        '-c:a', 'aac', '-b:a', '192k',
        '-movflags', '+faststart',
        $outfile,
    );

    print "ffmpeg: @ffcmd\n" if $DEBUG;

    # Check if file needs transcoding
    my $serve_file;
    if ($file =~ /\.(mp4|mkv|avi|mov|ts|flv|wmv)$/i && !$use_nvenc) {
        # Try serving original file directly (no transcode)
        $serve_file = $file;
        print "Serving original file (no transcode)\n";
    } else {
        # Transcode first
        print "Transcoding with ffmpeg" . ($use_nvenc ? " (NVENC)" : "") . "...\n";
        # GPU monitor if NVENC
        if ($use_nvenc) {
            system("tmux has-session -t tv 2>/dev/null || tmux new-session -d -s tv -n remote 'bash'");
            system("tmux new-window -t tv -n gpu 'watch -n1 nvidia-smi'");
        }
        system(@ffcmd);
        if ($? != 0) {
            die "ffmpeg failed\n";
        }
        $serve_file = $outfile;
        print "Transcode done: $serve_file\n";
    }

    # Serve file via HTTP
    my ($serve_dir, $serve_name) = $serve_file =~ m{^(.+)/([^/]+)$};
    _start_http_server($serve_dir, $http_port);

    my $encoded_name = $serve_name;
    $encoded_name =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge;
    my $stream_url = "http://$local_ip:$http_port/$encoded_name";
    print "Stream URL: $stream_url\n";

    # Send to TV via DLNA
    print "Sending to TV via DLNA...\n";
    _dlna_play($HOST, $stream_url);

    print "Casting to $HOST — Ctrl+C to stop\n";
    print "Stop with: $0 stop-cast\n";
}

sub cmd_stop_cast {
    my $pidfile = "/tmp/philipstv-cast.pid";
    if (-f $pidfile) {
        open(my $fh, '<', $pidfile);
        my $pid = <$fh>;
        chomp $pid;
        close($fh);
        if ($pid && kill(0, $pid)) {
            kill('TERM', $pid);
            print "Stopped ffmpeg (PID $pid)\n";
        }
        unlink $pidfile;
    } else {
        print "No active cast found\n";
    }
    # Send Back key to exit TV browser/player
    api_post('input/key', { key => 'Back' });
}

sub cmd_dlna_status {
    my $control_url = "http://$HOST:49152/avt_control";
    my $body = _soap_envelope('GetTransportInfo', '<InstanceID>0</InstanceID>');
    my $ua_plain = LWP::UserAgent->new(timeout => 10);
    my $req = HTTP::Request->new('POST', $control_url);
    $req->header('Content-Type' => 'text/xml; charset="utf-8"');
    $req->header('SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"');
    $req->content($body);
    my $res = $ua_plain->request($req);
    print "Status: " . $res->status_line . "\n";
    print $res->content . "\n";
}

sub cmd_helptv {
    print <<'TV';
=== TV Quick Reference ===

  on / wol          Wake TV (magic packet)
  status            Volume, channel, screen state
  vol+ / vol-       Volume up/down
  vol 20            Set volume
  mute / unmute     Toggle mute

  dlna-play FILE    Play local file on TV (auto HTTP server)
  dlna-play URL     Play remote URL on TV
  dlna-status       DLNA transport state
  stop-cast         Stop HTTP server + send Back key

  pause / play / stop   Playback control (key aliases)
  key Home / Back / Confirm / CursorUp/Down/Left/Right

  ch nova           Switch channel (partial match)
  channels          List all channels
  hdmi 1            Switch to HDMI input

  tv ~/Videos/      Open tmux TV dashboard for folder
  screen On/Off     Display on/off

  tv-screen [RES]   Virtual X screen on TV (Xephyr + NVENC capture)
                    Default 1920x1080. Run apps: DISPLAY=:1 firefox
  tv-screen-stop    Stop virtual screen

  system            Model, firmware, API version
  settings          Settings tree with node IDs
TV
}

sub cmd_tv_screen {
    my ($res) = @_;
    $res ||= '1920x1080';
    my $disp = ':1';

    # Prevent double run
    my $check = `pgrep -f "Xephyr $disp" 2>/dev/null`;
    if ($check && $check =~ /\d+/) {
        chomp $check;
        print "Xephyr already running on $disp (PID $check)\n";
        print "Use: tv-screen-stop to kill it first\n";
        return;
    }

    my $port = $CAST_PORT + 1;  # 8889
    my $local_ip = _get_local_ip();
    my $script = File::Spec->rel2abs($0);

    # Kill old stuff on port
    system("fuser -k $port/tcp >/dev/null 2>&1");
    sleep 1;

    # Ensure tmux tv session exists
    my $has_tv = !system("tmux has-session -t tv 2>/dev/null");
    unless ($has_tv) {
        system("tmux new-session -d -s tv -n remote 'bash'");
    }

    # Add screen window in tmux — runs Xephyr + WM + capture
    my $screen_cmd = join('; ',
        "echo '=== TV Screen: $disp ($res) ==='",
        "Xephyr $disp -screen $res -resizeable -no-host-grab &",
        "sleep 2",
        "DISPLAY=$disp xfwm4 &",
        "DISPLAY=$disp xterm &",
        "sleep 1",
        "echo '>>> Capture starting (NVENC)...'",
        "DISPLAY=$disp ffmpeg -f x11grab -framerate 25 -video_size $res -i $disp " .
            "-c:v h264_nvenc -preset p4 -b:v 10M -g 50 -c:a aac -b:a 192k " .
            "-movflags +frag_keyframe+empty_moov+default_base_moof " .
            "-f mp4 -listen 1 http://0.0.0.0:$port",
        "echo '>>> Screen capture ended'",
        "bash",
    );
    system("tmux new-window -t tv -n screen '$screen_cmd'");

    # nvidia-smi monitor window
    system("tmux new-window -t tv -n gpu 'watch -n1 nvidia-smi'");

    sleep 4;

    # DLNA play
    my $url = "http://$local_ip:$port";
    print "Stream: $url\n";
    _dlna_play($HOST, $url);

    print "=== TV Screen Active ===\n";
    print "Display: DISPLAY=$disp\n";
    print "Run: DISPLAY=$disp firefox\n";
    print "     DISPLAY=$disp vlc movie.mp4\n";
    print "tmux attach -t tv (window: screen)\n";
}

sub cmd_tv_screen_stop {
    my $disp = ':1';
    system("pkill -f 'Xephyr $disp'");
    system("fuser -k " . ($CAST_PORT + 1) . "/tcp 2>/dev/null");
    print "TV screen stopped\n";
    # Kill tmux window
    system("tmux kill-window -t tv:screen 2>/dev/null");
}

sub cmd_wol {
    die "No MAC address — set mac in ~/.philipstv.conf\n" unless $MAC;
    $MAC =~ s/[:-]//g;
    my $mac_bytes = pack('H12', $MAC);
    my $magic = "\xff" x 6 . $mac_bytes x 16;

    require IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
        Proto => 'udp',
        Broadcast => 1,
    ) or die "Cannot create socket: $!\n";
    my $dest = sockaddr_in(9, inet_aton('255.255.255.255'));
    $sock->send($magic, 0, $dest);
    $sock->close;

    print "WoL magic packet sent to $MAC\n";
}

sub cmd_tv {
    my ($file_or_dir) = @_;
    $file_or_dir ||= '.';

    use File::Spec;
    my $abs = File::Spec->rel2abs($file_or_dir);
    my $serve_dir = -d $abs ? $abs : (($abs =~ m{^(.+)/}) ? $1 : '.');
    my $port = $CAST_PORT;
    my $local_ip = _get_local_ip();
    my $script = File::Spec->rel2abs($0);

    # Kill old session
    system("tmux kill-session -t tv 2>/dev/null");
    system("fuser -k $port/tcp >/dev/null 2>&1");
    sleep 1;

    # Build file list for display
    my @files;
    opendir(my $dh, $serve_dir);
    while (my $f = readdir($dh)) {
        push @files, $f if $f =~ /\.(mp4|mkv|avi|mov|ts|flv|wmv|mp3|flac|ogg|wav|m4a|webm)$/i;
    }
    closedir($dh);

    # Create playlist file
    my $playlist = "/tmp/tv-playlist.txt";
    open(my $pl, '>', $playlist);
    my $i = 1;
    for my $f (sort @files) {
        printf $pl "%3d  %s\n", $i++, $f;
    }
    close($pl);

    # tmux session
    #  window 0: http — server с видими requests
    #  window 1: playlist — файлове за избор
    #  window 2: remote — интерактивен контрол
    # Start built-in Perl HTTP server (fork, background)
    _start_http_server($serve_dir, $port);
    system("tmux new-session -d -s tv -n http 'echo \"=== HTTP :$port — $serve_dir ===\"; while true; do ss -tn 2>/dev/null | grep $port | while read l; do echo \"\$(date +%H:%M:%S) \$l\"; done; sleep 2; done'");
    system("tmux new-window -t tv -n playlist 'cat $playlist; echo; echo \"Play: philipstv.pl dlna-play http://$local_ip:$port/FILENAME\"; echo \"Vol:  philipstv.pl vol+/vol-/mute\"; echo; bash'");
    # Write rc file with aliases
    my $rcfile = "/tmp/tv-remote.rc";
    open(my $rc, '>', $rcfile);
    print $rc "[ -f ~/.bashrc ] && source ~/.bashrc\n";
    print $rc "export HISTFILE=/tmp/tv-remote.history\n";
    print $rc "export HISTSIZE=500\n";
    print $rc "alias tv='$script'\n";
    print $rc "alias vol+='$script vol+'\n";
    print $rc "alias vol-='$script vol-'\n";
    print $rc "alias mute='$script mute'\n";
    print $rc "alias unmute='$script unmute'\n";
    print $rc "alias pause='$script key Pause'\n";
    print $rc "alias play='$script key Play'\n";
    print $rc "alias stop='$script key Stop'\n";
    print $rc "alias on='$script on'\n";
    print $rc "alias wol='$script wol'\n";
    print $rc "alias helptv='$script helptv'\n";
    print $rc "alias tv-screen='$script tv-screen'\n";
    print $rc "alias tv-screen-stop='$script tv-screen-stop'\n";
    print $rc "alias dlna-play='$script dlna-play'\n";
    print $rc "alias dlna-status='$script dlna-status'\n";
    print $rc "alias status='$script status'\n";
    print $rc "echo '=== TV Remote (arrow up for commands) ==='\n";
    close($rc);

    # Pre-populate history with all commands (newest last = first on arrow-up)
    my $histfile = "/tmp/tv-remote.history";
    open(my $hf, '>', $histfile);
    my @cmds = (
        'tv system',
        'tv settings',
        'tv channels',
        'tv-screen 1920x1080',
        'tv-screen-stop',
        'tv get audio/volume',
        'tv screen On',
        'tv screen Off',
        'tv hdmi 1',
        'tv ch nova',
        'tv key Home',
        'tv key Back',
        'tv key Confirm',
        'tv key CursorUp',
        'tv key CursorDown',
        'tv key Subtitle',
        'DISPLAY=:1 firefox &',
        'DISPLAY=:1 vlc movie.mp4 &',
        'DISPLAY=:1 xterm &',
        'dlna-play ~/Videos/',
        'dlna-status',
        'on',
        'wol',
        'stop',
        'pause',
        'play',
        'unmute',
        'mute',
        'vol-',
        'vol+',
        'tv vol 20',
        'helptv',
        'status',
    );
    print $hf "$_\n" for @cmds;
    close($hf);
    system("tmux new-window -t tv -n remote 'bash --rcfile $rcfile'");

    # GPU monitor if NVENC
    if ($NVENC) {
        system("tmux new-window -t tv -n gpu 'watch -n1 nvidia-smi'");
    }

    # If specific file given, play it
    if (-f $abs) {
        my ($name) = $abs =~ m{([^/]+)$};
        sleep 1;
        my $ename = $name;
        $ename =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge;
        my $url = "http://$local_ip:$port/$ename";
        print "Playing: $url\n";
        _dlna_play($HOST, $url);
        system("tmux send-keys -t tv:remote '$script dlna-status' Enter");
    }

    print "=== TV Session ===\n";
    print "tmux attach -t tv\n";
    print "Windows: http | playlist | remote\n";
    printf "Files: %d in %s\n", scalar @files, $serve_dir;
    print "URL base: http://$local_ip:$port/\n";

    # Attach
    exec("tmux attach -t tv");
}

sub cmd_dlna_play_url {
    my ($file_or_url) = @_;
    die "Usage: philipstv.pl dlna-play <file|url>\n" unless $file_or_url;

    my $url;
    if ($file_or_url =~ m{^https?://}) {
        $url = $file_or_url;
    } else {
        # Local file — serve it
        die "File not found: $file_or_url\n" unless -f $file_or_url;
        use File::Spec;
        my $abs = File::Spec->rel2abs($file_or_url);
        my ($dir, $name) = $abs =~ m{^(.+)/([^/]+)$};
        my $local_ip = _get_local_ip();
        _start_http_server($dir, $CAST_PORT);
        my $encoded = $name;
        $encoded =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge;
        $url = "http://$local_ip:$CAST_PORT/$encoded";
        print "Serving: $url\n";
    }

    my $control_url = "http://$HOST:49152/avt_control";
    print "SetAVTransportURI: $url\n";
    my $ok = _dlna_set_uri($control_url, $url);
    print "SetURI: " . ($ok ? "OK" : "FAILED") . "\n";
    if ($ok) {
        sleep 1;
        my $play_ok = _dlna_action($control_url, 'Play', '<Speed>1</Speed>');
        print "Play: " . ($play_ok ? "OK" : "FAILED") . "\n";
    }
}

sub _dlna_play {
    my ($tv_ip, $url) = @_;

    # Step 1: discover UPnP AVTransport service via SSDP
    my $location = _ssdp_discover($tv_ip);
    unless ($location) {
        warn "DLNA: SSDP discovery failed, trying default location\n";
        $location = "http://$tv_ip:49153/nmrDescription.xml";
    }
    print STDERR "DLNA location: $location\n" if $DEBUG;

    # Step 2: find AVTransport control URL
    my $control_url = _find_avtransport($location);
    unless ($control_url) {
        warn "DLNA: Cannot find AVTransport in XML, trying common paths\n";
        my ($base) = $location =~ m{^(https?://[^/]+)};
        for my $path ('/avt_control', '/upnp/control/AVTransport', '/AVTransport/control',
                      '/dmr/control/AVTransport', '/MediaRenderer/AVTransport/Control') {
            $control_url = "$base$path";
            print STDERR "DLNA: trying $control_url\n" if $DEBUG;
            if (_dlna_set_uri($control_url, $url)) {
                _dlna_action($control_url, 'Play', '<Speed>1</Speed>');
                print "DLNA: Playing on TV (via $path)\n";
                return;
            }
        }
        warn "DLNA: All paths failed\n";
        return;
    }

    # Step 3: SetAVTransportURI
    if (_dlna_set_uri($control_url, $url)) {
        # Step 4: Play
        _dlna_action($control_url, 'Play', '<Speed>1</Speed>');
        print "DLNA: Playing on TV\n";
    }
}

sub _ssdp_discover {
    my ($tv_ip) = @_;

    my $search = "M-SEARCH * HTTP/1.1\r\n" .
                 "HOST: 239.255.255.250:1900\r\n" .
                 "MAN: \"ssdp:discover\"\r\n" .
                 "MX: 3\r\n" .
                 "ST: urn:schemas-upnp-org:service:AVTransport:1\r\n\r\n";

    my $sock = IO::Socket::INET->new(
        Proto => 'udp',
        LocalPort => 0,
        Timeout => 3,
    ) or return undef;

    my $dest = sockaddr_in(1900, inet_aton($tv_ip));
    $sock->send($search, 0, $dest);

    my $buf;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 3;
        $sock->recv($buf, 4096);
        alarm 0;
    };
    $sock->close;

    if ($buf && $buf =~ /LOCATION:\s*(\S+)/i) {
        return $1;
    }
    return undef;
}

sub _find_avtransport {
    my ($location) = @_;
    my $ua_plain = LWP::UserAgent->new(timeout => 5);
    my $res = $ua_plain->get($location);
    return undef unless $res->is_success;

    my $xml = $res->content;
    my ($base) = $location =~ m{^(https?://[^/]+)};

    # Find AVTransport controlURL from description XML
    if ($xml =~ m{<controlURL>(/avt_control)</controlURL>}s ||
        $xml =~ m{AVTransport.*?<controlURL>([^<]+)</controlURL>}s ||
        $xml =~ m{<controlURL>([^<]*avt[^<]*)</controlURL>}si) {
        my $path = $1;
        $path = "$base$path" unless $path =~ /^https?:/;
        return $path;
    }
    return undef;
}

sub _dlna_set_uri {
    my ($control_url, $media_url) = @_;
    # Stop current playback first
    _dlna_action($control_url, 'Stop', '');
    $media_url = _url_encode_path($media_url);
    my $body = _soap_envelope('SetAVTransportURI',
        '<InstanceID>0</InstanceID>' .
        '<CurrentURI>' . _xml_escape($media_url) . '</CurrentURI>' .
        '<CurrentURIMetaData></CurrentURIMetaData>'
    );
    return _soap_post($control_url, 'SetAVTransportURI', $body);
}

sub _dlna_action {
    my ($control_url, $action, $args) = @_;
    $args ||= '';
    my $body = _soap_envelope($action, "<InstanceID>0</InstanceID>$args");
    return _soap_post($control_url, $action, $body);
}

sub _soap_envelope {
    my ($action, $body) = @_;
    return '<?xml version="1.0" encoding="utf-8"?>' .
           '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ' .
           's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">' .
           '<s:Body>' .
           '<u:' . $action . ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">' .
           $body .
           '</u:' . $action . '>' .
           '</s:Body></s:Envelope>';
}

sub _soap_post {
    my ($url, $action, $body) = @_;
    print STDERR "DLNA SOAP: $action → $url\n" if $DEBUG;
    my $ua_plain = LWP::UserAgent->new(timeout => 10);
    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'text/xml; charset="utf-8"');
    $req->header('SOAPAction' => "\"urn:schemas-upnp-org:service:AVTransport:1#$action\"");
    $req->content($body);
    my $res = $ua_plain->request($req);
    print STDERR "DLNA response: " . $res->status_line . "\n" if $DEBUG;
    print STDERR "DLNA body: " . $res->content . "\n" if $DEBUG && !$res->is_success;
    return $res->is_success;
}

sub _url_encode_path {
    my ($url) = @_;
    # Encode only the filename part (after last /)
    if ($url =~ m{^(https?://[^/]+/.*/?)([^/]+)$}) {
        my ($base, $file) = ($1, $2);
        $file =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge;
        return "$base$file";
    }
    return $url;
}

sub _xml_escape {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    return $s;
}

sub _start_http_server {
    my ($dir, $port) = @_;
    my $pidfile = "/tmp/philipstv-http.pid";

    # Kill anything on this port
    system("fuser -k $port/tcp >/dev/null 2>&1");
    sleep 1;

    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) {
        chdir $dir or die "Cannot chdir to $dir: $!\n";
        $SIG{CHLD} = 'IGNORE';  # auto-reap children

        my $srv = IO::Socket::INET->new(
            LocalPort => $port,
            Listen    => 10,
            ReuseAddr => 1,
            Proto     => 'tcp',
        ) or die "Cannot bind :$port: $!\n";

        while (my $client = $srv->accept()) {
            my $child = fork();
            if ($child == 0) {
                close $srv;
                _http_handle($client, $dir);
                close $client;
                exit 0;
            }
            close $client;
        }
        exit 0;
    }

    # Save PID
    open(my $fh, '>', $pidfile);
    print $fh "$pid\n";
    close($fh);

    sleep 1;
    print "HTTP server started on :$port (PID $pid, serving $dir)\n";
    return $pid;
}

sub _http_handle {
    my ($client, $dir) = @_;

    local $/ = "\r\n";
    my $request_line = <$client>;
    return unless $request_line;
    chomp $request_line;

    my ($method, $path) = $request_line =~ m{^(GET|HEAD)\s+(/\S*)\s+HTTP/};
    return unless $method && $path;

    # Read and discard headers
    while (my $hdr = <$client>) {
        chomp $hdr;
        last if $hdr eq '';
    }

    # URL decode
    $path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $path =~ s{^/}{};
    $path =~ s{\.\./}{}g;  # prevent traversal

    my $file = "$dir/$path";

    unless (-f $file && -r $file) {
        print $client "HTTP/1.1 404 Not Found\r\n";
        print $client "Content-Length: 0\r\n";
        print $client "Connection: close\r\n\r\n";
        return;
    }

    my $size = -s $file;
    my $ext = ($file =~ /\.(\w+)$/)[0] || '';
    my %mime = (
        mp4 => 'video/mp4', mkv => 'video/x-matroska', avi => 'video/x-msvideo',
        webm => 'video/webm', mov => 'video/quicktime', ts => 'video/mp2t',
        mp3 => 'audio/mpeg', flac => 'audio/flac', ogg => 'audio/ogg',
        wav => 'audio/wav', m4a => 'audio/mp4', srt => 'text/plain',
    );
    my $ct = $mime{lc $ext} || 'application/octet-stream';

    print $client "HTTP/1.1 200 OK\r\n";
    print $client "Content-Type: $ct\r\n";
    print $client "Content-Length: $size\r\n";
    print $client "Accept-Ranges: bytes\r\n";
    print $client "Connection: close\r\n\r\n";

    if ($method eq 'GET') {
        open(my $fh, '<:raw', $file) or return;
        my $buf;
        while (read($fh, $buf, 65536)) {
            print $client $buf or last;
        }
        close $fh;
    }
}

sub _get_local_ip {
    # Find local IP on same network as TV
    my $output = `ip route get $HOST 2>/dev/null`;
    if ($output =~ /src\s+(\d+\.\d+\.\d+\.\d+)/) {
        return $1;
    }
    return undef;
}

sub cmd_pair {
    # Step 1: Get system info first (for featuring data)
    my $ua_noauth = LWP::UserAgent->new(
        ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
        timeout  => 10,
    );

    print "Fetching system info...\n";
    my $sys_res = $ua_noauth->get("$BASE_HTTP/system");
    my $sys = $sys_res->is_success ? decode_json($sys_res->content) : {};

    # Generate device ID
    my $device_id = '';
    $device_id .= sprintf("%02x", int(rand(256))) for 1..16;

    my $device = {
        device_name => hostname(),
        device_os   => 'Linux',
        type        => 'native',
        id          => $device_id,
        app_id      => 'philipstv.pl',
        app_name    => 'philipstv.pl',
    };

    my $request_data = {
        access => {
            scope => ['read', 'write', 'control'],
        },
        device => $device,
    };

    # Add featuring if available
    if ($sys->{featuring}) {
        $request_data->{access}{featuring} = $sys->{featuring};
    }

    # Step 2: Send pair request (no auth, use HTTPS)
    print "Sending pair request...\n";
    my $req = HTTP::Request->new('POST', "$BASE/pair/request");
    $req->header('Content-Type' => 'application/json');
    $req->content(encode_json($request_data));
    my $res = $ua_noauth->request($req);

    unless ($res->is_success) {
        die "Pair request failed: " . $res->status_line . "\n";
    }

    my $resp = decode_json($res->content);
    if (($resp->{error_id} || '') ne 'SUCCESS') {
        die "Pair request error: " . encode_json($resp) . "\n";
    }

    my $timestamp = $resp->{timestamp};
    my $auth_key  = $resp->{auth_key};

    print "TV is showing a PIN code.\n";
    print "Enter PIN: ";
    chomp(my $pin = <STDIN>);

    # Step 3: Calculate HMAC signature
    my $hmac = Digest::HMAC_SHA1->new($AUTH_SHARED_KEY);
    $hmac->add($timestamp);
    $hmac->add($pin);
    my $signature = encode_base64($hmac->digest, '');

    # Step 4: Send pair grant (with digest auth using device_id:auth_key)
    my $grant_data = {
        device => $device,
        auth   => {
            auth_AppId    => '1',
            auth_timestamp => $timestamp,
            auth_signature => $signature,
            pin            => $pin,
        },
    };

    my $ua_pair = LWP::UserAgent->new(
        ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
        timeout  => 10,
    );
    $ua_pair->credentials("$HOST:$PORT", 'XTV', $device_id, $auth_key);

    my $grant_req = HTTP::Request->new('POST', "$BASE/pair/grant");
    $grant_req->header('Content-Type' => 'application/json');
    $grant_req->content(encode_json($grant_data));
    my $grant_res = $ua_pair->request($grant_req);

    unless ($grant_res->is_success) {
        die "Pair grant failed: " . $grant_res->status_line . "\n" .
            $grant_res->content . "\n";
    }

    my $grant_resp = decode_json($grant_res->content);
    if (($grant_resp->{error_id} || '') ne 'SUCCESS') {
        die "Pair grant error: " . encode_json($grant_resp) . "\n";
    }

    print "\n=== Pairing successful! ===\n";
    print "Username: $device_id\n";
    print "Password: $auth_key\n";
    print "\nUse with: philipstv.pl --user $device_id --pass $auth_key\n";
}

# --- Helpers ---

sub api_post_get {
    my ($path, $data) = @_;
    my $url = "$BASE/$path";
    my $body = encode_json($data);
    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'application/json');
    $req->content($body);
    my $res = $ua->request($req);
    return undef unless $res->is_success;
    return decode_json($res->content);
}

my %_channel_cache;
sub get_channel_name {
    my ($ccid) = @_;
    return undef unless $ccid;
    load_channels() unless %_channel_cache;
    return $_channel_cache{$ccid};
}

sub find_channel {
    my ($search) = @_;
    load_channels() unless %_channel_cache;
    # Exact ccid match
    return $search if $_channel_cache{$search};
    # Name search (case insensitive)
    my $lc = lc($search);
    for my $ccid (keys %_channel_cache) {
        return $ccid if lc($_channel_cache{$ccid}) eq $lc;
    }
    # Partial match
    for my $ccid (keys %_channel_cache) {
        return $ccid if index(lc($_channel_cache{$ccid}), $lc) >= 0;
    }
    return undef;
}

sub load_channels {
    my $db = api_get('channeldb/tv') or return;
    for my $list (@{$db->{channelLists} || []}) {
        my $id = $list->{id};
        my $data = api_get("channeldb/tv/channelLists/$id") or next;
        for my $ch (@{$data->{Channel} || []}) {
            $_channel_cache{$ch->{ccid}} = $ch->{name} if $ch->{ccid} && $ch->{name};
        }
    }
}

sub print_settings_tree {
    my ($node, $depth) = @_;
    return unless ref $node eq 'HASH';
    my $indent = "  " x $depth;
    if ($node->{node_id}) {
        printf "%s[%d] %s\n", $indent, $node->{node_id}, $node->{string_id} || '';
    }
    if ($node->{node} && ref $node->{node} eq 'ARRAY') {
        for my $child (@{$node->{node}}) {
            print_settings_tree($child, $depth + 1);
        }
    }
}

sub print_help {
    print <<'HELP';
philipstv.pl — Philips TV CLI (JointSpace API v6)

Usage: philipstv.pl [options] <command> [args]

Options:
  --host IP        TV IP address (required, or set in config file)
  --port PORT      API port (default: 1926)
  --user USER      Digest auth username (from pairing)
  --pass PASS      Digest auth password (from pairing)
  --conf FILE      Config file path (default: ~/.philipstv.conf)
  --debug          Show HTTP requests
  --help           This help

Config file (searched in order: --conf, ~/.philipstv.conf):
  host = 192.168.1.100
  user = your_username_here
  pass = your_password_here

Commands:
  status           Show current TV status (volume, channel, context)
  system           Show TV model, serial, firmware, API version

  vol              Show current volume
  vol <N>          Set volume to N (0-60)
  vol+ [step]      Volume up (default +3)
  vol- [step]      Volume down (default -3)
  mute             Mute
  unmute           Unmute

  ch               Show current channel
  ch <name|ccid>   Switch channel (by name or ccid, partial match)
  channels         List all channels

  source           Show current source
  sources          List all sources
  source <id>      Switch source

  hdmi [N]         Switch to HDMI-N input (default: 1)
                   Position configurable in ~/.philipstv.conf:
                     hdmi1_pos = 5

  pair             Pair with TV (interactive, shows PIN on screen)

  key <KeyName>    Send remote key (Standby, VolumeUp, CursorUp,
                   Confirm, Back, Home, Play, Pause, Digit0-9, ...)

  screen           Show screen state
  screen <On|Off>  Set screen state

  settings         Show settings tree with node IDs
  setting-get <id> Get setting value by node ID
  setting-set <id> '<json>' Set setting value

  cast <file|url>  Stream video to TV via ffmpeg HTTP + JointSpace
                   Options: --nvenc (RTX GPU encode), --port N (default 8888)
  stop-cast        Stop active cast

  get <path>       Raw GET from API path
  post <path> '<json>' Raw POST to API path

Examples:
  philipstv.pl --host 192.168.1.100 pair
  philipstv.pl status
  philipstv.pl vol+ 5
  philipstv.pl ch "BBC One"
  philipstv.pl key Standby
  philipstv.pl get audio/volume
  philipstv.pl system

Tested on:
  Philips 43PUS7810/12 (4K UHD, API v6.1.0, Linux)
HELP
}

__END__

=head1 NAME

philipstv.pl - Philips TV CLI control via JointSpace API v6

=head1 SYNOPSIS

  philipstv.pl [options] <command> [args]

  # First time — pair with TV:
  philipstv.pl --host 192.168.1.100 pair

  # Then use normally:
  philipstv.pl status
  philipstv.pl vol+ 5
  philipstv.pl ch "BBC One"

=head1 DESCRIPTION

Command-line tool for controlling Philips Smart TVs via the JointSpace
HTTP/HTTPS API (version 6). Pure Perl, fully standalone — including
pairing. Uses Digest Authentication for secured endpoints.

=head1 OPTIONS

=over 4

=item B<--host> I<IP>

TV IP address. Required, or set in F<~/.philipstv.conf>.

=item B<--port> I<PORT>

API port. Default: 1926.

=item B<--user> I<USER>

Digest auth username (obtained from pairing).

=item B<--pass> I<PASS>

Digest auth password (obtained from pairing).

=item B<--debug>

Show HTTP requests to stderr.

=item B<--help>

Show usage help.

=back

=head1 COMMANDS

=head2 Pairing

=over 4

=item B<pair>

Interactive pairing with the TV. The TV will display a PIN code on screen.
Enter it and receive username/password credentials. No Python or external
tools needed.

=back

=head2 Status

=over 4

=item B<status>

Show current TV status: volume, channel, context, screen state.

=item B<system>

Show TV model, serial number, firmware, API version, OS type.

=back

=head2 Volume

=over 4

=item B<vol>

Show current volume level.

=item B<vol> I<N>

Set volume to I<N> (0-60).

=item B<vol+> [I<step>]

Increase volume by I<step> (default 3).

=item B<vol-> [I<step>]

Decrease volume by I<step> (default 3).

=item B<mute>

Mute the TV.

=item B<unmute>

Unmute the TV.

=back

=head2 Channels

=over 4

=item B<ch>

Show current channel.

=item B<ch> I<name|ccid>

Switch to channel by name (case-insensitive, partial match) or ccid.

=item B<channels>

List all available channels with ccid, name, and preset number.

=back

=head2 Sources

=over 4

=item B<source>

Show current input source.

=item B<sources>

List all available input sources.

=item B<source> I<id>

Switch to input source by ID.

=back

=head2 Remote Control

=over 4

=item B<key> I<KeyName>

Send a remote control key press. Common keys: Standby, VolumeUp, VolumeDown,
Mute, CursorUp, CursorDown, CursorLeft, CursorRight, Confirm, Back, Home,
Options, Play, Pause, Stop, Digit0 through Digit9.

=back

=head2 Screen

=over 4

=item B<screen>

Show current screen state.

=item B<screen> I<On|Off>

Set screen state (turn display on or off).

=back

=head2 Settings

=over 4

=item B<settings>

Show the settings menu tree with node IDs.

=item B<setting-get> I<node_id>

Get the current value of a setting by node ID.

=item B<setting-set> I<node_id> I<'json_value'>

Set a setting value by node ID. Value must be valid JSON.

=back

=head2 Raw API Access

=over 4

=item B<get> I<path>

Raw GET request to an API path. Returns JSON.

=item B<post> I<path> I<'json_data'>

Raw POST request to an API path with JSON body.

=back

=head1 CONFIGURATION

Credentials can be stored in F<~/.philipstv.conf> to avoid typing
them on every invocation:

  host = 192.168.1.100
  user = your_username_here
  pass = your_password_here

Command-line options override config file values.

=head1 REQUIREMENTS

=over 4

=item * Perl 5

=item * C<LWP::UserAgent> (libwww-perl)

=item * C<JSON>

=item * C<IO::Socket::SSL>

=item * C<LWP::Authen::Digest>

=item * C<Digest::HMAC_SHA1> (for pairing)

=item * C<MIME::Base64> (core)

=back

On Gentoo:

  emerge dev-perl/libwww-perl dev-perl/JSON dev-perl/IO-Socket-SSL dev-perl/Digest-HMAC

=head1 TESTED ON

=over 4

=item * Philips 43PUS7810/12 (4K UHD, API v6.1.0, Linux)

=back

Should work with other Philips Android/Linux TVs supporting JointSpace API v6.

=head1 REPOSITORY

L<https://github.com/smooker/philipstv>

=head1 LICENSE

GNU General Public License v3.0 - see LICENSE file.

=head1 AUTHOR

smooker E<lt>smooker@smooker.orgE<gt>, with Claude

=cut
