# Toolchain and Learning Path

## Recommended solo-developer toolchain

You do not need every application. The strongest free workflow for this project is:

```text
Inkscape (shapes, frames, icons, SVG masters)
        ↓
Krita (paint, texture, highlights, wear, PNG export)
        ↓
Godot (layout, states, data, interaction, scaling)
```

Optional applications:

- **Figma:** fast wireframes, screen flows, spacing systems, and reusable components. It is excellent for deciding layout before painting.
- **Blender:** render ornate bevels, embossed metal, medallions, and consistent lighting when a painted 2D result is difficult.
- **Affinity Designer/Photo or Adobe Illustrator/Photoshop:** paid substitutes for the Inkscape/Krita roles. Do not buy them merely because the reference looks professional; technique and a coherent component system matter more than the brand of software.

Official learning references:

- [Inkscape learning resources](https://inkscape.org/learn/)
- [Krita layers and masks](https://docs.krita.org/en/reference_manual/layers_and_masks.html)
- [Figma UI design](https://www.figma.com/ui-design-tool/)
- [Blender bevel modifier](https://docs.blender.org/manual/en/latest/modeling/modifiers/generate/bevel.html)
- [Illustrator and Photoshop comparison](https://www.adobe.com/creativecloud/design/illustrator-vs-photoshop.html)
- [Godot GUI containers](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html)
- [Godot Theme](https://docs.godotengine.org/en/stable/classes/class_theme.html)
- [Godot NinePatchRect](https://docs.godotengine.org/en/stable/classes/class_ninepatchrect.html)
- [Godot TextureButton](https://docs.godotengine.org/en/stable/classes/class_texturebutton.html)

## What to learn, in order

### 1. Interface hierarchy

Learn to decide what the player must see first, second, and only on demand. Practise using size, contrast, position, grouping, whitespace, and typography rather than adding ornament everywhere.

For a grand-strategy HUD, the usual hierarchy is:

1. Critical alerts and current selection.
2. Date, pause, and speed.
3. Resources and their rate of change.
4. Navigation to major systems.
5. Detailed breakdowns in tooltips and windows.

### 2. Vector construction

In Inkscape or a vector editor, learn:

- Rectangle, ellipse, Bézier/path, node, and Boolean tools.
- Fill, stroke, gradient, clipping mask, and path effects.
- Alignment, distribution, snapping, grids, symbols, and reusable components.
- Creating clean silhouettes at small sizes.
- Exporting exact pixel dimensions while retaining an editable SVG master.

Use vectors for frames, dividers, simple icons, crests, masks, flourishes, and button silhouettes.

### 3. Raster material painting

In Krita or a raster editor, learn:

- Non-destructive layers, groups, masks, clipping groups, and adjustment/filter layers.
- Soft highlights, contact shadows, bevels, edge wear, subtle grain, and controlled colour variation.
- Tileable textures and seamless-offset checking.
- Alpha-channel cleanup and export without halos.
- Downscaling with visual inspection at actual game size.

Use raster painting for leather, parchment, aged metal, painted event art treatment, portraits, and subtle surface variation. Texture must support readability; it must not compete with text.

### 4. Modular component design

Learn to make a small library that creates many screens:

- One window frame that stretches through nine-slicing.
- One sub-panel with light and dark variants.
- A button family with complete states.
- One tab family.
- Reusable headers, dividers, badges, slots, progress bars, scroll bars, and tooltips.
- Shared spacing and type tokens.

A single giant painted UI image is not a usable interface. It cannot resize, localise, animate, or change state cleanly.

### 5. Godot UI construction

Learn these Godot concepts before implementing the final skin:

- `Control` anchors and offsets.
- `MarginContainer`, `HBoxContainer`, `VBoxContainer`, `GridContainer`, `ScrollContainer`, and `TabContainer`.
- Size flags and custom minimum sizes.
- `Theme`, `ThemeVariation`, fonts, font sizes, constants, icons, and `StyleBoxTexture`.
- `NinePatchRect` for stretchable art.
- `TextureButton` or themed `Button` for stateful controls.
- Focus neighbours, tooltips, mouse filters, and keyboard/controller navigation.
- Signals and presentation binding without placing game rules in UI scripts.

## Rebuilding the supplied top-left reference

### Step 1: treat it as a mood reference

Do not cut the JPEG into production pieces. Its checkerboard is part of the pixels, it has JPEG compression, it contains a complete flattened layout, and its design provenance has not been approved. Observe only its broad ideas: a shield anchor, a horizontal resource strip, circular/arched slots, a lower navigation row, antique metal trim, and dark recessed surfaces.

### Step 2: make a wireframe first

At 1× scale, begin around 850–1000 pixels wide and 170–220 pixels tall. The exact final width must be tested against the date/speed cluster and alert row at 1152×648. Author raster source art at 2× resolution.

Block out only:

- Country shield and clickable country identity area.
- Six to eight resource cells.
- Date/pause/speed zone or a clear handoff to the centred date cluster.
- Alert strip.
- Major-window navigation buttons.

Do not add filigree until the information fits at the minimum supported resolution.

### Step 3: split it into assets

Create editable masters and transparent exports for:

- `frame_hud_left`
- `frame_hud_middle`
- `frame_hud_right`
- `frame_country_shield`
- `mask_country_shield`
- `slot_resource`
- `slot_alert`
- `button_major_window`
- `badge_notification_count`
- `divider_hud`
- Resource and navigation icons

Country flag/shield artwork must remain separate from the shield frame so the selected country can change at runtime. Temporary country art must never be baked into the frame.

### Step 4: build every interaction state

For buttons, slots, and tabs, create and test:

- Normal
- Hover
- Pressed
- Selected/toggled
- Keyboard focus
- Disabled
- Warning/urgent where relevant

Keep state differences clear at actual size. A hover state should not rely on a two-percent brightness change that disappears on another monitor.

### Step 5: export correctly

- Keep SVG, Krita, Figma, or Blender sources outside runtime import folders or under a clearly separated `source/` tree.
- Export runtime PNGs with a clean alpha channel in sRGB.
- Never export interface art as JPEG.
- Export at 2× where downscaling improves quality, but verify memory and import settings.
- Use descriptive names and keep borders transparent beyond the intended visual edge.
- Do not bake text, dynamic numbers, country names, flags, dates, or keyboard prompts into artwork.

### Step 6: implement as layout, not a picture

The Godot scene should resemble:

```text
PersistentHUD
├── CountryIdentity
│   ├── ShieldFrame
│   ├── CountryEmblem
│   └── CountryNameTooltipTarget
├── ResourceStrip
│   └── ResourceCell × N
├── AlertStrip
│   └── AlertButton × N
├── TimeControls
└── MajorWindowButtons
```

Each resource cell should bind an icon, current value, change indicator, warning state, and breakdown tooltip. It should not contain economic calculations.

## Four-week beginner practice plan

### Week 1: tools and fundamentals

- Complete basic Inkscape shape/path exercises.
- Complete Krita layers/masks and alpha-export exercises.
- Recreate a plain panel, divider, and one icon without ornament.
- Inspect them at 100%, 75%, 50%, and 125% UI scale.

### Week 2: component set

- Make one 64×64 navigation button in every state.
- Make one nine-slice window frame and deliberately stretch it to five sizes.
- Make one resource cell, one tooltip, one tab pair, and one progress bar.
- Put them into a Godot test scene using a shared Theme.

### Week 3: persistent HUD

- Wireframe the top-left HUD at 1152×648 first.
- Build resource and alert components.
- Add the shield frame and a temporary project-owned emblem.
- Test long values, negative values, hidden resources, and urgent alerts.

### Week 4: first real window

- Reskin the province window using the shared component set.
- Add tabs, scroll behaviour, empty states, and tooltips.
- Test mouse, keyboard, different UI scales, and long translated strings.
- Record problems in the asset register before creating more windows.

## First exercise

Create one original 64×64 square button with a simple building icon. Produce normal, hover, pressed, selected, focused, and disabled states; export them with transparency; build the button in a small Godot test scene; then view it at 1152×648 and 1920×1080. If that single component remains clear, consistent, and responsive, use it as the seed for the whole interface family.

