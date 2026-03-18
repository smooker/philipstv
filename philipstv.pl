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

my $HOST     = '';
my $PORT     = 1926;
my $API      = 6;
my $USER     = '';
my $PASS     = '';
my $DEBUG    = 0;
my $HELP     = 0;

GetOptions(
    'host=s'   => \$HOST,
    'port=i'   => \$PORT,
    'api=i'    => \$API,
    'user=s'   => \$USER,
    'pass=s'   => \$PASS,
    'debug'    => \$DEBUG,
    'help'     => \$HELP,
) or die "Bad options. Try --help\n";

my $CMD  = shift @ARGV || '';
my @ARGS = @ARGV;

if ($HELP || !$CMD) {
    print_help();
    exit 0;
}

# Load config from ~/.philipstv.conf if exists
my $CONFFILE = ($ENV{HOME} || '/tmp') . "/.philipstv.conf";
if (-f $CONFFILE) {
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
  --host IP        TV IP address (required, or set in ~/.philipstv.conf)
  --port PORT      API port (default: 1926)
  --user USER      Digest auth username (from pairing)
  --pass PASS      Digest auth password (from pairing)
  --debug          Show HTTP requests
  --help           This help

Config file (~/.philipstv.conf):
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
