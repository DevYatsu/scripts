#!/usr/bin/env nu

# ==============================================
# - League of Legends Build Tracker -
#
# This script fetches item builds for LoL champions from onetricks.gg.
# Supports both standard Summoner's Rift and ARAM modes.
#
#  Usage:
#   > main build "Miss Fortune"
#   > main aram "Lee Sin"
#
#  Features:
#   - Fetches boots, starting items, popular items
#   - Shows frequent bans (Summoner's Rift only)
#   - Computes most frequent full build paths
#
# Created by: Yatsu :)
# ==============================================

# Entry point
def main [character_name: string] {
  main build $character_name
}

# Build mode
def "main build" [character_name: string] {
  show_build $character_name "builds"
}

# ARAM mode
def "main aram" [character_name: string] {
  show_build $character_name "aram"
}

# Shared logic for both modes
def show_build [character_name: string, mode: string] {
  print "🔍 Sending request..."

  let c_name = normalize_name $character_name
  let url = $"https://www.onetricks.gg/fr/champions/($mode)/($c_name)"

  let file_content = (
    try {
      http get $url
    } catch {
      return $"'($character_name)' is not a valid LoL Character"
    }
  )

  let data = parse_file $file_content $mode

  if $mode == "builds" {
    print "\n🔒 Frequent Bans:"
    $data.bans | take 3 | each {|b| print $"  - ($b)" }
  }

  print "\n🛡️ Starting Items:"
  $data.start_items | take 2 | each {|set|
    print "  Set:"
    $set | each {|item| print $"    - ($item)" }
  }

  print "\n👢 Boots:"
  $data.boots | take 3 | each {|b| print $"  - ($b)" }

  print "\n🧱 Build Path:"
  $data.mains | each {|set|
    print "  Set:"
    $set | each {|item| print $"    - ($item)" }
  }

  print "\n🧪 Popular Items:"
  $data.popular_items | take 5 | each {|item| print $"  - ($item)" }

  if $mode == "builds" {
    print "\n🔮 Runes coming soon..."
  }
}

# Converts "Lee Sin" → "LeeSin"
def normalize_name [name: string] {
  if ($name | str contains " ") {
    $name | split words | str join
  } else {
    $name
  }
}

# Parses the HTML and extracts build data
def parse_file [raw: string, mode: string] {
  let start_tag = '<script id="__NEXT_DATA__" type="application/json">'
  let end_tag = '</script>'

  let json_str = (
    $raw
    | split row $start_tag
    | get 1
    | split row $end_tag
    | first
  )

  let json = $json_str | from json
  let props = $json | get props.pageProps
  let items = $props.itemData

  let patch = (
    if $mode == "builds" {
      $props.patchList | last
    } else {
      "all"
    }
  )

  let stats = $props.buildStats | get $patch

  let bans = (
    if $mode == "builds" {
      try { $props.bans | each {|b| $b.banId } } catch { [] }
    } else {
      []
    }
  )

  let boots = $stats.boots | each {|b| $items | get ($b | first) | get name }

  let start_items = $stats.startingItems | each {|i|
    $i | first | each {|id| $items | get $id | get name }
  }

  let all_start = ($stats.boots ++ $stats.startingItems)
    | each {|i| $i | first }
    | flatten
    | flatten

  let popular_items = $stats.popularItems | each {|i|
    $items | get ($i | first) | get name
  }

  # Build Path (mains)
  let mains_data = (
    if $mode == "aram" {
      $props.mainsData | each {|m| $m.path }
    } else {
      $props.matchHistory
      | each {|m|
          $m.timeline.orderedItems
          | each {|i| $i | into string }
          | where {|id| $id not-in $all_start }
          | take 3
          | str join ","
        }
    }
  )

  let mains = $mains_data
    | reduce --fold {} {|entry, acc|
        let key = $entry
        try {
          $acc | update $key (($acc | get $key) + 1)
        } catch {
          $acc | insert $key 1
        }
      }
    | transpose k v
    | sort-by v -r
    | take 3
    | each {|e|
        $e.k
        | split row ","
        | each {|id| $items | get $id | get name }
      }

  return {
    boots: $boots,
    start_items: $start_items,
    popular_items: $popular_items,
    bans: $bans,
    mains: $mains
  }
}
