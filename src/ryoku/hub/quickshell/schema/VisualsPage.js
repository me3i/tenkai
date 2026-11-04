.pragma library

// VisualsPage as data: the compositor's visual surface (blur, shadow, gaps,
// borders, rounding and the screen shader). The page applies every change
// live and persists it through its own hypr-visual.json (the Hub's atomic
// write path), so these rows exist for the global search and the
// compositor-driving section marker, not for the shared schema renderer.
// Nothing here goes through hub.draft.

var rows = [
    {
        "tab": "",
        "group": "BLUR",
        "key": "visuals.blur_enabled",
        "label": "Blur",
        "desc": "Frosted-glass behind windows and layer surfaces.",
        "ctl": "sw",
        "src": "hypr-visual.json"
    },
    {
        "tab": "",
        "group": "BLUR",
        "key": "visuals.blur_size",
        "label": "Blur size",
        "desc": "How large the blur sample area is.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 1.0,
        "hi": 8.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "BLUR",
        "key": "visuals.blur_passes",
        "label": "Blur passes",
        "desc": "How many times the blur is applied.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 1.0,
        "hi": 3.0
    },
    {
        "tab": "",
        "group": "SHADOW",
        "key": "visuals.shadow_enabled",
        "label": "Shadow",
        "desc": "Drop shadow beneath windows.",
        "ctl": "sw",
        "src": "hypr-visual.json"
    },
    {
        "tab": "",
        "group": "SHADOW",
        "key": "visuals.shadow_range",
        "label": "Shadow range",
        "desc": "How far the shadow reaches from the window.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 0.0,
        "hi": 80.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "SHADOW",
        "key": "visuals.shadow_render_power",
        "label": "Shadow power",
        "desc": "How hard the shadow falls off.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 1.0,
        "hi": 4.0
    },
    {
        "tab": "",
        "group": "SHAPE",
        "key": "visuals.rounding",
        "label": "Corner rounding",
        "desc": "Radius applied to every window and layer surface.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 0.0,
        "hi": 20.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "SHAPE",
        "key": "visuals.border_size",
        "label": "Border size",
        "desc": "Thickness of the border drawn around windows.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 0.0,
        "hi": 5.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "SHAPE",
        "key": "visuals.active_border",
        "label": "Active border",
        "desc": "Colour of the focused window's border.",
        "ctl": "color",
        "src": "hypr-visual.json"
    },
    {
        "tab": "",
        "group": "SHAPE",
        "key": "visuals.inactive_border",
        "label": "Inactive border",
        "desc": "Colour of every unfocused window's border.",
        "ctl": "color",
        "src": "hypr-visual.json"
    },
    {
        "tab": "",
        "group": "SPACING",
        "key": "visuals.gaps_in",
        "label": "Gaps between windows",
        "desc": "Space between tiles.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 0.0,
        "hi": 30.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "SPACING",
        "key": "visuals.gaps_out",
        "label": "Gaps around the screen",
        "desc": "Space between windows and the screen edge.",
        "ctl": "slid",
        "src": "hypr-visual.json",
        "lo": 0.0,
        "hi": 40.0,
        "unit": "px"
    },
    {
        "tab": "",
        "group": "SCREEN SHADER",
        "key": "visuals.screen_shader",
        "label": "Screen shader",
        "desc": "Full-screen filter baked into the compositor; none clears it.",
        "ctl": "seg",
        "src": "hypr-visual.json",
        "opts": [
            "none",
            "grain",
            "vignette",
            "halftone",
            "bone",
            "onebit"
        ]
    }
];
