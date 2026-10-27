# Windows glass contour regression — 0.13.1

The Windows shell used `0.25 * 0.035` opacity (0.875%) with a physical material lit only by ambient light. It had no environment reflections to reveal the silhouette; the optical textures attenuated their own transparency further. The previous smoke checks verified geometry and controls but did not require visible body contrast.

The fix replaces that shell material with a view-dependent reflection shader on the existing continuous quartic mesh. Soft pale highlights read against dark desktops; a gradual dark refraction reads against pale desktops. The center remains transparent. Theme colors affect the reflections, while the minimum contour does not depend on the glow slider or an environment map. No twelve-edge frame or opaque face plates were added.

## Executed evidence

- RED: [run 40461764553](https://github.com/gd0306/t-cube/actions/runs/40461764553), old material: both Windows jobs failed the new resting-size visibility test. Neither background had pixels exceeding the required contrast; center alpha was 0.0118.
- An intermediate reflection passed dark-background visibility but failed the pale-background test. The refraction transition was widened based on that result.
- GREEN: [run 40462294246](https://github.com/gd0306/t-cube/actions/runs/40462294246), commit `009ef6c`: both Windows runners passed all 58 behavior tests, type checks, build, source installation and runtime smoke. Shader compilation and real framebuffer pixels are checked by the installed app.
- The test hides icon decals while reading the framebuffer so icons cannot falsely satisfy body visibility. It composites the result mathematically over dark/light backgrounds, requires at least 0.4% of viewport pixels to differ by 18/255 or more, and requires center alpha below 0.12. Observed visible coverage: dark 12.14%, light 0.729%; center alpha 0.0235 (97.65% transparent).
- Inspected native Windows captures at resting 164 DIP and hovered 656 DIP on both backgrounds. Updated README captures come from this run. User data is isolated for all tests.

These are Windows Server CI images; physical Windows 10/11 display calibration and wallpaper still vary. The regression now checks the previously missed contrast requirement directly. Existing interaction and configuration tests remain green.

Update by quitting the installed app, pulling `master`, and rerunning `windows/scripts/install.ps1`; existing configuration is preserved.
