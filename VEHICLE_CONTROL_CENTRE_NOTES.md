# Vehicle Control Centre - Future Features

## Overview
The orphaned engineer system stores metadata that will be used for a future Vehicle Control Centre GUI.

## Stored Metadata for Orphaned Engineers

Each orphaned engineer stores:
- `entity` - Reference to the dummy engineer entity
- `unit_number` - Unit number of the dummy engineer
- `player_index` - Which player owns this connection
- `vehicle_id` - Unit number of the vehicle
- `vehicle_type` - Type of vehicle (spider-vehicle, locomotive, car)
- `vehicle_surface` - Surface index where the vehicle is located
- `disconnected_at` - Game tick when disconnected
- `disconnect_reason` - Why it was kept alive:
  - "crafting" - Has active crafting queue
  - "has_items" - Has items in main inventory
  - "has_logistic_items" - Has items in logistic trash
  - "multiple" - Combination of above
  - "none" - Should not be kept alive (will be cleaned up)

## Planned GUI Features

### Active Connections Tab
- List all active remote connections
- Show vehicle name/type, player name, connection duration
- Quick disconnect button

### Orphaned Connections Tab
- List all orphaned engineers
- Display:
  - Vehicle name/type
  - Time since disconnect (formatted as "X minutes ago")
  - Reason kept alive (e.g., "Crafting 3 items", "Has 50 iron plates")
  - Vehicle location (surface name)
- Quick reconnect button for each connection
- Manual cleanup button (force destroy)
- Filter/sort options

### Favorites System (Future)
- Mark vehicles as favorites
- Quick access to favorite vehicles
- Auto-reconnect to favorites

## Storage Location
All orphaned engineer data is stored in:
```lua
storage.orphaned_dummy_engineers[engineer_unit_number] = {
    -- metadata as described above
}
```

## Access Functions
- `neural_disconnect.find_orphaned_engineer_for_vehicle(vehicle)` - Find orphaned engineer for a vehicle
- `neural_disconnect.should_keep_alive(engineer)` - Check if engineer should be kept alive
- `neural_disconnect.get_disconnect_reason(engineer)` - Get reason why kept alive
- `neural_disconnect.force_destroy_orphaned_engineer(engineer, player_index, show_message)` - Force destroy an orphaned engineer

