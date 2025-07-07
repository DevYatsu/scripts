#!/usr/bin/env nu

# ==============================================
# - League of Legends Build Tracker (Nushell) -
#
# This script fetches item builds for LoL champions from onetricks.gg.
# Supports both standard Summoner's Rift and ARAM modes.
#
#  Usage:
#   > main build "Miss Fortune"
#   > main aram "Lee Sin"
#
#  Features:
#   - Fetches and parses item builds (boots, starting items, popular items)
#   - Shows frequent bans (for standard mode)
#
# Created by: Yatsu :)
# ==============================================

def main [character_name: string] {
  main build $character_name
}

# Entry point for build mode (standard)
def "main build" [character_name: string] {
  show_build $character_name "builds"
}

# Entry point for ARAM mode
def "main aram" [character_name: string] {
  show_build $character_name "aram"
}

# Unified logic for both build and aram modes
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

  let body = parse_file $file_content $mode

  if $mode == "builds" {
    print "\n🔒 Frequent Bans:"
    print ($body.bans | take 3)
  }

  print "\n🛡️ Starting Items:"
  $body.start_items | take 2 | each {|set|
    print "  Set:"
    print $set 
  }

  print "\n👢 Boots:"
  $body.boots | take 3 | each {|b| print $"  - ($b)" }

  print "Build Path"
  $body.mains | each {|item| 
    print "  Set:"
    print $item
  }

  print "\n🧪 Popular Items:"
  $body.popular_items | take 5 | each {|item| print $"  - ($item)" }

  if $mode == "builds" {
    print "\n🔮 Runes coming soon..."
    print "📦 Entire build coming soon..."
  }
}

# Cleans and formats a character name (e.g., "Lee Sin" → "LeeSin")
def normalize_name [name: string] {
  if ($name | str contains " ") {
    return ($name | split words | str join)
  } else {
    return $name
  }
}

# Parses the HTML and extracts the build data
def parse_file [raw: string, mode: string] {
  let start_sep = '<script id="__NEXT_DATA__" type="application/json">'
  let end_sep = '</script>'

  let json_str = (
    $raw
    | split row $start_sep
    | get 1
    | split row $end_sep
    | first
  )

  let json = $json_str | from json
  let props = $json | get props.pageProps
  let items = $props | get itemData

  mut last_patch = "all"
  if $mode == "builds" {
    $last_patch = $props.patchList | last
  }

  let build_stats = $props.buildStats | get $last_patch

  mut bans = []
  if $mode == "builds" {
    $bans = $props.bans | each {|b| $b.banId }
  }

  let boots = (
    $build_stats.boots
    | each {|b| $items | get ($b | first) | get name }
  )

  let start_items = (
    $build_stats.startingItems
    | each {|i|
        $i | first
        | each {|id| $items | get $id | get name }
      }
  )
  let all_start_items = ($build_stats.boots ++ $build_stats.startingItems) | each {|i|$i|first} | flatten | flatten

  let popular_items = (
    $build_stats.popularItems
    | each {|i| $items | get ($i | first) | get name }
  )
  
  mut mains_data = []
  if mode != "aram" {
    # for rift only
    $mains_data = $props | get matchHistory | each {|m| $m.timeline.orderedItems | each {|i| $i | into string} | where $it not-in $all_start_items | take 3 | str join ","}
  } else {
    # for aram only
    $mains_data =  $props | get mainsData | each {|m| $m.path}
  }

  let counter = $mains_data | reduce --fold {} {|match, acc|
      let s = $match
      try {
        $acc | update $s (($acc | get $s) + 1)
      } catch {
        $acc | insert $s 0
      }
  } |
    transpose k v | sort-by v --reverse |
    take 3 | each {|e| $e.k | split row "," | each {|id| $items | get $id | get name}}
  
  return {
    boots: $boots,
    start_items: $start_items,
    popular_items: $popular_items,
    bans: $bans,
    mains: $counter
  }
}
