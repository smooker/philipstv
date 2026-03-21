# philipstv — TODO

## Subtitles
- [x] **BUG**: Philips 43PUS7810/12 DLNA player crash-ва при смяна на subtitle track (key Subtitle → BG → Enter). Workaround: remux с BG subs като stream 0 + default flag:
  ```
  ffmpeg -i input.mkv -map 0:v -map 0:a -map 0:s:BG -map 0:s:EN -c copy -disposition:s:0 default -disposition:s:1 0 output.mkv
  ```
  TV-то взима първия subtitle track автоматично — работи!
- [ ] Автоматичен remux в dlna-play: detect BG subtitle track, сложи го като default
- [ ] Варианти: DIDL-Lite metadata, ffmpeg burn-in (--nvenc), external .srt serve

## HTTP server
- [ ] python3 http.server умира при определени условия — tmux window се затваря
- [ ] Да не затваря window-а при crash (bash fallback)

## Cast
- [ ] Автоматичен Screen On / WoL преди cast
- [ ] Playlist mode — поредица от файлове
