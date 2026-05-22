# Firmware regression checklist

Run each. Mark ✓ working, ✗ broken, ~ partial. Note HTTP status / behavior.

## Info / read-only
- [ ] `./philipstv.pl status`
- [ ] `./philipstv.pl system`
- [ ] `./philipstv.pl tv`                          — current channel/activity
- [ ] `./philipstv.pl channels`                    — channel list
- [ ] `./philipstv.pl sources`                     — input list
- [ ] `./philipstv.pl settings`                    — settings dump
- [ ] `./philipstv.pl setting_get <node_id>`
- [ ] `./philipstv.pl screen`                      — screen state

## Volume
- [ ] `./philipstv.pl vol 20`
- [ ] `./philipstv.pl vol+`
- [ ] `./philipstv.pl vol-`
- [ ] `./philipstv.pl mute`
- [ ] `./philipstv.pl unmute`

## Keys / navigation
- [ ] `./philipstv.pl key home`
- [ ] `./philipstv.pl key back`
- [ ] `./philipstv.pl key ok`
- [ ] `./philipstv.pl key up / down / left / right`

## Input / sources
- [ ] `./philipstv.pl source <id>`
- [ ] `./philipstv.pl hdmi 1`
- [ ] `./philipstv.pl channel <num>`

## Activities / apps
- [ ] `./philipstv.pl browser https://ice.smooker.org`
- [ ] `./philipstv.pl post activities/launch '{"id":"browser","url":"http://ice.smooker.org/"}'`
- [ ] `./philipstv.pl post activities/launch '{"id":"<app-id>"}'`

## Power / WoL
- [ ] `./philipstv.pl wol`                         — magic packet
- [ ] `./philipstv.pl key standby`                 — sleep

## DLNA / cast
- [ ] `./philipstv.pl dlna-status`
- [ ] `./philipstv.pl dlna-play http://<host>/video.mp4`
- [ ] `./philipstv.pl cast <file>`
- [ ] `./philipstv.pl stop-cast`

## Pairing (only if creds reset)
- [ ] `./philipstv.pl pair`

## Raw API
- [ ] `./philipstv.pl get system`
- [ ] `./philipstv.pl get activities/current`
- [ ] `./philipstv.pl get applications`
- [ ] `./philipstv.pl post <path> <json>`
