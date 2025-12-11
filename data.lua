data:extend({
    {
        type = "custom-input",
        name = "neural-spidertron-inventory",
        key_sequence = "SHIFT + E",
        consuming = "game-only"
    },
    {
      type = "custom-input",
      name = "reconnect-to-last-vehicle",
      key_sequence = "SHIFT + Z",
      consuming = "game-only"
    },
})

data:extend({
  {
    type = "shortcut",
    name = "reconnect-last-vehicle",
    action = "lua",
    localised_name = {"shortcut-name.reconnect-last-vehicle"},
    order = "a[neural]-a[reconnect]",
    icon = "__base__/graphics/icons/spidertron.png",
    small_icon = "__base__/graphics/icons/spidertron.png",
    style = "blue"
  }
})

data:extend({
  {
    type = "sprite",
    name = "neural-connection-sprite",
    filename = "__neural-spider-control__/graphics/icons/neural-connection.png",
    priority = "extra-high",
    width = 64,
    height = 64
  }
})