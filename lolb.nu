#!/usr/bin/env nu

# ==================================================
# 🧠 League of Legends Build Tracker - Nushell
#
# Fetches item builds from https://www.onetricks.gg
#
# Usage:
#   > main build "Miss Fortune" --lang fr
#   > main aram "Lee Sin"
#
# Features:
#   - Boots, starting items, popular items
#   - Frequent bans (Rift only)
#   - Frequent build paths
#   - Runes (simplified)
#
# Author: Yatsu :)
# ==================================================

# ---------- CLI Commands ----------

def main [character_name: string, --lang (-l): string = "en"] {
  validate_locale $lang (metadata $lang).span
  main build -l $lang $character_name
}

def "main build" [--lang (-l): string = "en", character_name: string] {
  validate_locale $lang (metadata $lang).span
  fetch_and_show $character_name $lang "builds"
}

def "main aram" [--lang (-l): string = "en", character_name: string] {
  validate_locale $lang (metadata $lang).span
  fetch_and_show $character_name $lang "aram"
}

# ---------- Core Logic ----------

def fetch_and_show [character_name: string, lang: string, mode: string] {
  print "🔍 Sending request..."

  let name = normalize_name $character_name
  let url = $"https://www.onetricks.gg/($lang)/champions/($mode)/($name)"

  let raw = try {
    http get $url
  } catch {
    print $"⚠️  Failed to reach: ($url)"
    return
  }

  let data = parse_build $raw $mode

  if $mode == "builds" {
    show_list "🔒 Frequent Bans" ($data.bans|take 3)
  }

  show_nested "Runes" $data.runes
  show_nested "🛡️ Starting Items" $data.start_items
  show_list "👢 Boots" ($data.boots|take 3)
  show_nested "🧱 Build Path" $data.mains
  show_list "🧪 Popular Items" ($data.popular_items|take 5)
  return
}

def parse_build [raw: string, mode: string] {
  let json = (
    $raw
    | split row '<script id="__NEXT_DATA__" type="application/json">'
    | get 1
    | split row '</script>'
    | first
    | from json
  )

  let props = $json.props.pageProps
  let items = $props.itemData
  let patch = if $mode == "builds" { $props.patchList | last } else { "all" }
  let stats = $props.buildStats | get $patch

  let bans = if $mode == "builds" {
      try { $props.bans | each {|b| $b.banId } } catch { [] }
    } else { [] }
  

  let all_start_ids = ($stats.boots ++ $stats.startingItems)
    | each {|i| $i | first }
    | flatten | flatten

  let boots = $stats.boots | each {|b| $items | get ($b | first) | get name }
  let start_items = $stats.startingItems | each {|i|
    $i | first | each {|id| $items | get $id | get name }
  }

  let popular_items = $stats.popularItems | each {|i|
    $items | get ($i | first) | get name
  }
  
  let raw_runes = $stats.popRunes
      | transpose k v
      | each {|r| $"($r.k),($r.v|first|last|first)"}
  let runes = filter_most_frequent $raw_runes
      | each {|e|
        $e.k
        | split row ","
        | each {|id| try {$props.runes|get keystone |get $id} catch {$props.runes|get subStyle |get $id}| get name}        
      }
       
  let mains_data = (
    if $mode == "aram" {
      $props.mainsData | each {|m| $m.path }
    } else {
      $props.matchHistory
      | each {|m|
          $m.timeline.orderedItems
          | each {|i| $i | into string }
          | where {|id| $id not-in $all_start_ids }
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
    runes: $runes
  }
}

# ---------- Display Helpers ----------

def show_list [title: string, values: list] {
  print $"($title)"
  $values | each {|v| print $"  - ($v)" }
}

def show_nested [title: string, sets: list<list<string>>] {
  print $"($title)"
  $sets | each {|set|
    print "  Set:"
    $set | each {|item| print $"    - ($item)" }
  }
}

# ---------- Utilities ----------

def normalize_name [name: string] {
  $name | split words | str join
}

def validate_locale [lang: string, span: any] {
  let locales = [en de es fr ko ja pl pt zh tr]
  if not ($lang in $locales) {
    error make {
      msg: "Invalid locale"
      label: {
        text: "Valid locales: en, de, es, fr, ko, ja, pl, pt, zh, tr"
        span: $span
      }
    }
  }
}

def filter_most_frequent [entries: list<string>] {
  $entries
    | reduce --fold {} {|entry, acc|
        try {
          $acc | update $entry (($acc | get $entry) + 1)
        } catch {
          $acc | insert $entry 1
        }
      }
    | transpose k v
    | sort-by v -r
    | take 3
}
