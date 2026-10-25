# Idle PD — app icons

Final launcher art, wired into Godot (DECISIONS #243).

| File | Role |
|------|------|
| `idle_pd_512.png` | Flat composite → copied to `res://icon.png` (editor + web export icon) |
| `idle_pd_192.png` | Android `launcher_icons/main_192x192` (NN from 512) |
| `idle_pd_fg_432.png` | Android adaptive foreground |
| `idle_pd_bg_432.png` | Android adaptive background |
| `idle_pd_mono_432.png` | Android monochrome / themed icon |
| `idle_pd.ico` | Windows exe + `windows_native_icon` |
| `favicon_16.png` / `favicon_32.png` | Browser tabs (copied by `tools/deploy_web.sh`) |
| `idle_pd_master_32.png` | Pixel source reference |
| `idle_pd_guide_512.png` / `mockup_preview.png` | Guides only — not used by export |

Edit the art here, then:

1. Copy `idle_pd_512.png` over `res://icon.png` (or re-run the copy step in implement).
2. Keep export paths in `export_presets.cfg` pointing at this folder.
3. Rebuild `idle_pd.ico` if small sizes change (multi-size ICO for Explorer/taskbar).

`tools/gen_branding_icons.py` regenerates **templates** and will overwrite finals — do not run it over finished art.
