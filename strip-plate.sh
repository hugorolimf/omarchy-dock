#!/bin/bash
# Removes the neutral plate some apps paint behind their logo (the dark
# squircle of Obsidian and Zen), so the logo sits directly on the dock.
#
#   strip-plate.sh <cache-dir> <icon-name-or-file>...
#
# Prints "<icon>\t<clean-png>" for each icon that has a plate. Icons
# without one print nothing and keep their artwork: a coloured plate is part of
# the brand and a light one can't be told from a sheet of paper (Evince), so
# only near-black plates count.
set -u
cache=$1
shift
mkdir -p "$cache"

# Points in a 256 px icon: just inside each edge (logos can reach far out, like
# Obsidian's gem), then inside each rounded corner. Printed as 0-255 r g b a.
fx=""
for p in 128,12 128,243 12,128 243,128 52,52 203,52 52,203 203,203; do
  x=${p%,*}
  y=${p#*,}
  fx+="%[fx:round(255*p{$x,$y}.r)] %[fx:round(255*p{$x,$y}.g)] %[fx:round(255*p{$x,$y}.b)] %[fx:round(255*p{$x,$y}.a)]\n"
done

# The largest file for an icon name, in the folders where apps install theirs.
find_icon() {
  local name=$1 dir size file
  [[ $name == /* ]] && { printf '%s' "$name"; return; }
  for dir in "$HOME/.local/share/icons/hicolor" /usr/share/icons/hicolor \
             "$HOME/.local/share/flatpak/exports/share/icons/hicolor" /var/lib/flatpak/exports/share/icons/hicolor; do
    [[ -r $dir/scalable/apps/$name.svg ]] && { printf '%s' "$dir/scalable/apps/$name.svg"; return; }
    for size in 1024 512 256 192 128 96 64 48; do
      file=$dir/${size}x$size/apps/$name.png
      [[ -r $file ]] && { printf '%s' "$file"; return; }
    done
  done
  for file in "/usr/share/pixmaps/$name.svg" "/usr/share/pixmaps/$name.png"; do
    [[ -r $file ]] && { printf '%s' "$file"; return; }
  done
}

for name in "$@"; do
  icon=$(find_icon "$name")
  [[ -r $icon ]] || continue
  out=$cache/$(printf '%s' "$icon" | md5sum | cut -c1-16)-$(stat -c %Y "$icon").png
  skip=$out.none
  [[ -e $skip ]] && continue
  if [[ -e $out ]]; then
    printf '%s\t%s\n' "$name" "$out"
    continue
  fi
  # Rendered large and on transparency: SVGs default to small, on white.
  read_opts=(-background none)
  [[ $icon == *.svg ]] && read_opts+=(-density 300)

  # Sample, then decide: all opaque, all alike, no colour.
  plate=$(magick "${read_opts[@]}" "$icon" -bordercolor none -border 1 -trim +repage -resize '256x256!' \
      -format "$fx" info: 2>/dev/null | awk '
    {
      n++
      hi = $1; if ($2 > hi) hi = $2; if ($3 > hi) hi = $3
      lo = $1; if ($2 < lo) lo = $2; if ($3 < lo) lo = $3
      if ($4 < 250 || hi - lo > 12) bad = 1
      if (n == 1 || hi > top) top = hi
      if (n == 1 || lo < bot) bot = lo
      r += $1; g += $2; b += $3
    }
    END {
      if (bad || n < 8 || top - bot > 40) exit
      printf "%d %d %d", r / n, g / n, b / n
    }')
  if [[ -z $plate ]]; then
    : > "$skip"
    continue
  fi
  read -r r g b <<< "$plate"
  (( (r + g + b) / 3 > 70 )) && { : > "$skip"; continue; }

  # Largest per-channel distance from the plate colour, as a soft alpha. The
  # plate's own highlight and the logo's anti-aliased edge fall in the ramp.
  tmp=$out.$$
  if magick "${read_opts[@]}" "$icon" -resize 512x512 -gravity center -extent 512x512 "PNG32:$tmp.base.png" 2>/dev/null \
    && magick "$tmp.base.png" -alpha off \( +clone -fill "rgb($r,$g,$b)" -colorize 100 \) \
         -compose difference -composite -separate -evaluate-sequence max -level 11%,20% -alpha off "$tmp.key.png" \
    && magick "$tmp.base.png" -alpha extract "$tmp.alpha.png" \
    && magick "$tmp.key.png" "$tmp.alpha.png" -compose multiply -composite \
         -morphology erode disk:1 -blur 0x0.6 "$tmp.mask.png" \
    && magick "$tmp.base.png" "$tmp.mask.png" -compose CopyAlpha -composite -compose over \
         -trim +repage -resize 448x448 -background none -gravity center -extent 512x512 "PNG32:$tmp.out.png" 2>/dev/null \
    && mv "$tmp.out.png" "$out"; then
    printf '%s\t%s\n' "$name" "$out"
  else
    : > "$skip"
  fi
  rm -f "$tmp".*.png
done
