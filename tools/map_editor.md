# Map Editor

Run from the project root:

```bash
love . --map-editor
```

Exports are written to:

```text
data/map_files
```

Controls:

- Left click / drag: place hexes
- Right click / drag: erase hexes
- `S`: toggle start marker on the hovered hex
- `E`: edit the hovered hex's spawn event string, then `Enter` saves or `Esc` cancels
- `R`: paint room hexes
- `C`: paint corridor hexes
- `D`: door mode
- In door mode, left click two adjacent existing hexes to toggle a door
- In door mode, right click or `Esc` cancels the current door selection
- `1`-`9`: load palette 1-9 from `assets/map_palettes`
- `0`: load palette 10 from `assets/map_palettes`
- `,` / `.`: select previous / next color swatch
- `Tab`: toggle R/C tile labels, where `R` is a room hex and `C` is a corridor hex
- Middle mouse drag: pan canvas
- Hold `Space` and drag: pan canvas
- Mouse wheel: adjust editor hex display size
- `Enter` or keypad `Enter`: export map
- `A`: save as the next unused `map_###.lua`
- `L`: load the current map file, or the first map file if none is active
- `[` / `]`: load previous / next map file
- `Delete` / `Backspace`: clear current map
- `Home`: reset camera
- `Esc`: quit

Dirty-state protection:

- `*` beside the filename means the map has unsaved changes.
- Press `Enter` twice to overwrite a loaded dirty map.
- Save As always writes to the next unused map file and then makes it active.
- Press load / previous / next twice to discard unsaved changes and load another map.
- Press clear twice to discard unsaved changes and clear the map.

Export format:

```lua
return {
    id = "map_001",
    tiles = {
        { q = 0, r = 0, start = true, palette = 1, swatch = 1, color = { 0.2800, 0.4200, 0.3600, 1.0000 } },
        { q = 1, r = 0, corridor = true, spawn_event = "ENEMY_ID", palette = 1, swatch = 2, color = { 0.2100, 0.3200, 0.2900, 1.0000 } },
    },
    doors = {
        { a = { q = 0, r = 0 }, b = { q = 1, r = 0 } },
    },
}
```
