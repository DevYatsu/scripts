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
  print "Sending request..."
  mut c_name = $character_name
  if ($character_name | str contains " ") {
    $c_name = $c_name | split words | str join 
  }
  mut file_content = ""
  try {
    $file_content = http get $"https://www.onetricks.gg/fr/champions/ranking/($c_name)"
  } catch {
    return $"'($character_name)' is not a valid LoL Character"
  }
  
  let body = parse_file $file_content "build"
    
  # Print starting items (nested lists)
  print "--- Starting Items ---"
  print ($body.start_items | take 2 | each {|i| $i | str join ' --> '})
  
  # Print boots
  print "--- Boots ---"
  print ($body.boots | take 3)

  # Print popular items
  print "--- Popular Items ---"
  print ($body.popular_items | take 5)

  print "--- Frequent Bans ---"
  print ($body.bans | take 3)

  print "Runes coming soon..."
  print "Entire build coming soon..."
}  

def "main build" [character_name: string] {
  main $character_name
}

def "main aram" [character_name: string] {
  print "Sending request..."
  mut c_name = $character_name
  if ($character_name | str contains " ") {
    $c_name = $c_name | split words | str join 
  }
  mut file_content = ""
  try {
    $file_content = http get $"https://www.onetricks.gg/fr/champions/aram/($c_name)"
  } catch {
    return $"'($character_name)' is not a valid LoL Character"
  }

  let body = parse_file $file_content "aram"

  # Print starting items (nested lists)
  print "--- Starting Items ---"
  print ($body.start_items | take 2 | each {|i| $i | str join ' --> '})
  
  # Print boots
  print "--- Boots ---"
  print ($body.boots | take 3)

  # Print popular items
  print "--- Popular Items ---"
  print ($body.popular_items | take 5)
}

def parse_file [raw: string, mode: string] {
  let start_sep =  '<script id="__NEXT_DATA__" type="application/json">'
  let end_sep = '</script>'

  let json_str = $raw | split row $start_sep | get 1 | split row $end_sep | first 
  let json = $json_str | from json
  let page_props = $json | get props.pageProps

  let items = $page_props | get itemData  

  mut last_patch = "all"
  try {
    # for rift only
    $last_patch =  $page_props | get patchList | last
  }
  mut bans = []
  try {
    # for rift only
    $bans = $page_props | get bans | each {|b| $b.banId}
  }
  let build_stats = $page_props | get buildStats | get ($last_patch)

  let boots: list<string>  = $build_stats | get boots | each {|b| $items | get ($b | first) | get name}
  let start_items: list<list<string>> = $build_stats |
      get startingItems |
      each {|i| $i | first | each {|id| $items | get $id | get name}}
  let popular_items: list<string> = $build_stats | get popularItems | each {|i| $items | get ($i | first) | get name}

  mut mains_data = []
  if mode != "aram" {
    # for rift only
    $mains_data = $page_props | get rankings | select not small_all_time |  get mainsData | each {|m| $m.path}
  } else {
    # for aram only
    $mains_data =  $page_props | get mainsData | each {|m| $m.path}
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
  $counter | each {|c| print $c}    
  return {boots: $boots, start_items: $start_items, popular_items: $popular_items, bans: $bans}
}

