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
def main [character_name: string, --lang (-l): string = "en"] {
  validate_locale $lang (metadata $lang).span
  main build -l $lang $character_name
}

# Build mode
def "main build" [--lang (-l): string = "en", character_name: string] {
  validate_locale $lang (metadata $lang).span
  show_build $character_name $lang "builds" 
}

# ARAM mode
def "main aram" [--lang (-l): string = "en", character_name: string] {
  validate_locale $lang (metadata $lang).span
  show_build $character_name $lang "aram"
}

# Shared logic for both modes
def show_build [character_name: string, lang: string, mode: string] {
  print "🔍 Sending request..."

  let c_name = normalize_name $character_name
  let url = $"https://www.onetricks.gg/($lang)/champions/($mode)/($c_name)"
 
  let file_content = (
    try {
      http get $url
    } catch {
      print "Is the character name valid ?"
      return $"Failed to reach endpoint '($url)'"
    }
  )

  let data = parse_file $file_content $mode

  if $mode == "builds" {
    print "\n🔒 Frequent Bans:"
    $data.bans | take 3 | each {|b| print $"  - ($b)" }
  }

  print "\n Runes"
  $data.runes | take 2 | each {|set|
    print "  Set:"
    $set | each {|item| print $"    - ($item)" }
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
}

# Converts "Lee Sin" → "LeeSin"
def normalize_name [name: string] {
   $name | split words | str join
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

  let champs = $props.championKeys | transpose k v | each {|i| $i.v}
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

  let skill_path = $stats.skillPaths | each {|i| $i | first}
  let runes = $stats.popRunes | transpose k v | each {|r| $"($r.k),($r.v|first|last|first)"}
  let best_runes = filter_most_frequent $runes
  | each {|e|
        $e.k
        | split row ","
        | each {|id| try {$props.runes|get keystone |get $id} catch {$props.runes|get subStyle |get $id}| get name}        
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

  let mains = filter_most_frequent $mains_data
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
    mains: $mains,
    champs: $champs,
    skills: $skill_path,
    runes: $best_runes
  }
}

def validate_locale [lang: string, span: any] {
  let locales = [en de es fr ko ja pl pt zh tr]
  if not ($lang in $locales) {
    error make {
      msg: "Invalid locale"
      label: {
        text: "Valid locales are: en, de, es, fr, ko, ja, pl, pt, zh, tr"
        span: $span
      }
    }
  }
}

def filter_most_frequent [target: list] {
  $target
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
}

# we would need to store names in each lang or user would be limited
# to only one lang, otherwise we could allow anything the first time
# and then store the characters but it requires more efforts 
# 
# def get_champs [] {
#   open champs.json | get champions | transpose k v | each {|i| $i.v}
# }

# def get_last_update [] {
#   try {
#     open champs.json | get lastUpdated | into datetime 
#   } catch {
#     null
#   }
# }

# def get_updated_champs [lang: string] {
#   let content = http get $"http://onetricks.gg/($lang)/champions/builds/Shaco"
#   let body = parse_file $content "aram"
#   $body.champs
# }

