# Prophecy Data — Mapping zu Foundation+Heads

Quelle: [doc/backlog/2026-06-08_tag_foundation_architecture.md](../../doc/backlog/2026-06-08_tag_foundation_architecture.md)

`tags/` enthält das ML-Vokabular (Embedding-Targets).  `names/` enthält
Display-Sample-Pools (kein Embedding, runtime rolls für Naming).  Jeder
Kategorie-Folder gehört direkt zu einem Head der Foundation-Architektur:

| Kategorie | Head | Rolle | tags/ | names/ |
|---|---|---|---|---|
| `items/` | `item_head` | Output: Items per Action-Composition | weapon, armor, tool, ... pro item_type | per-item-type Pool (weapon.txt, armor.txt, ...) |
| `diseases/` | `disease_head` | Output: Diseases (7 kinds) | per-kind + universal_disease_tags | per-kind nouns + adjective + epidemic_names |
| `skills/` | `skill_head` | Output: Skills (5 kinds) | per-kind skill_tags + skill_only_tags | per-kind skill name pools |
| `pets/` | `pet_head` (future) | Output: Pet-Creatures | pet_tags | adj + noun |
| `enemies/` | `world_entity_head` (= discovergen Head 1) | Output: Enemies | combat | adj + noun |
| `growables/` | `world_entity_head` | Output: Growables | growth_process | adj + noun |
| `harvestables/` | `world_entity_head` | Output: Harvestables | harvest_process | adj + noun |
| `npcs/` | `world_entity_head` | Output: NPCs | personality | adj + noun |
| `portals/` | `world_entity_head` | Output: Portals | stability | adj + noun |
| `locked_things/` | `world_entity_head` | Output: Locked entities | lock_kind | adj + noun |
| `zone/` `terrain/` `weather/` `realm/` | **Input-Kontext für alle Heads** | Welt-Kontext-Tags | zone, terrain, weather, realm tags | (kein name-pool — Zone/Terrain/Weather sind fix) |
| `common/` | **Foundation (cross-cutting)** | Universal tags | common_tags | — |
| `actions/` | **Foundation** (kein Head) | Inhärente Verben jeder Creature | (keine Tags, siehe README im File) | grund_aktionen.txt (6 fix) |

## Was kommt später noch dazu

- `combat_score_head` hat keinen eigenen Datenordner — er liest **aus**
  `items/` + `skills/` (att/def Tag-Bags) und produziert nur einen Score.
  Trainings-Korpus lebt in `data/combat.txt` im Projekt-Root.
- Cross-Cutting-Tag-Domains (`material:*`, `element:*`, `*_class:*`) sind
  **noch nicht** in eigenen Files — sie sind in den Per-Kategorie-Tag-Files
  verteilt.  V0.1: Konsolidieren in `tags/common/` (oder eigenes
  `tags/cross_cutting/` Folder).

## Naming-Konvention

- Tag-Files heißen `<domain>_tags.txt` oder `<process>.txt` (z.B. combat.txt
  ist *_tags weggelassen weil eigenes Vokabular)
- Name-Pools: `noun.txt` und `adjective.txt` für generische Kategorien
  (enemy/growable/npc/...), spezifische Items haben eigene `<type>.txt`
- Sub-Folder erlaubt (siehe `items/craft_materials/{animal,metal,...}.txt`)

## Atlas-Keys

Der Builder (`prophecy/sources/main.aiml`) generiert Keys nach dem Pattern:
```
<kind>:<domain>:<name>
```
- kind ∈ {tag, name, adj}
- domain wird aus dem Pfad abgeleitet (kategorisch + ggf. sub-kategorisch)
- name ist der einzelne Token

Beispiel:
- File `tags/items/weapon_tags.txt` mit Zeile `bludgeoning`
  → Key `tag:items:weapon_tags:bludgeoning`
- File `names/enemies/adjective.txt` mit Zeile `feral`
  → Key `adj:enemies:feral`
- File `names/items/weapon.txt` mit Zeile `hammer`
  → Key `name:items:weapon:hammer`
