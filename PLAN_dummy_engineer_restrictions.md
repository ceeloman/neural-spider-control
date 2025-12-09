# Restrict Dummy Engineer Trash Slots and Prevent Armor/Weapons

## Changes Required

### 1. Modify `neural_connect.lua` - After Dummy Engineer Creation

**Location**: `scripts/neural_connect.lua` around line 571-616 (after dummy engineer is created and before player is assigned)

**Changes**:
- After creating the dummy engineer entity (line 562-571), add code to:
  1. **Restrict trash slots**: Get the trash inventory and call `set_bar(10)` to limit it to 10 slots
  2. **Clear armor**: Get the armor inventory and clear it
  3. **Clear weapons**: Get the guns inventory and clear it

**Code location**: After line 571 (after `if not dummy_engineer then return end`) and before line 579 (before setting bonuses)

### 2. Optional: Add Periodic Check or Event Handler

**Location**: `control.lua` or `neural_connect.lua`

**Option A** (Simpler): Only clear at creation time - players could re-equip but it's simpler
**Option B** (More robust): Add periodic check or event handler to prevent re-equipping

**Recommendation**: Start with Option A (clear at creation), add Option B if needed based on testing.

## Implementation Details

- Use `dummy_engineer.get_inventory(defines.inventory.character_trash)` to get trash inventory
- Call `trash_inventory.set_bar(10)` to restrict to 10 slots
- Use `dummy_engineer.get_inventory(defines.inventory.character_armor)` and `clear()` to remove armor
- Use `dummy_engineer.get_inventory(defines.inventory.character_guns)` and `clear()` to remove weapons

## Files to Modify

1. `scripts/neural_connect.lua` - Add restrictions after dummy engineer creation (around line 571-578)



this is from the api, do we need to create a character in the data stage and use that for dummy characters?

Just do deep copy and change or somehting?
create_character(character?) → boolean
Creates and attaches a character entity to this player.

The player must not have a character already connected and must be online (see LuaPlayer::connected).

Parameters
character	:: EntityWithQualityID?	
The character to create else the default is used.

Return values
→ boolean	
Whether the character was created.