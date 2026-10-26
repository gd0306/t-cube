# Soft glass body — 0.12.0 (build 20)

## Visual change

The launcher now uses a closed cubic superellipsoid with a continuous curved silhouette. The twelve-edge outline and six separate sheen plates are removed from the renderer. A transparent clearcoat shell, soft moving pearl reflection and theme tint describe one glass body; existing material-specific inner light remains subtle while choosing an app.

The six logical shortcut groups, icon planes, collider and picking coordinates retain their existing layout. Icons float around the body while hovered. Rotation, positioning, hover enlargement, Ctrl dragging and launch modes are unchanged. Previous public frame geometry remains available but is no longer used by the renderer.

## Verification

- `swift test --scratch-path .build/tests --filter SoftGlassGeometryTests` passed two new geometry tests: bounded rounded shape, hand-calculated diagonal point, closed topology, outward triangles, continuous unit normals and finite UVs.
- `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed 4 XCTest, 40 native Swift Testing and 61 core cases, including all direct-launch and drag regressions.
- A subsequent native preview run passed an added backdrop-response assertion: the rendered body's center visibly responds to a dark/light background change. This checks transparency beyond material settings alone.
- Native dark, light, idle and hover captures were inspected. README's matching PNG/GIF gallery was regenerated using system sample icons and an isolated temporary configuration.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh` and `git diff --check` passed. The DMG's application, executable, signature and installation links were verified.
- Independent read-only review found no definite correctness, interaction, geometry-seam or icon-obscuration regression. Geometry and neutral optical resources are cached; animation does not rebuild them per frame.

## Evidence and limits

The opt-in exporter writes `.build/glass-previews/soft-body-{dark,warm,light,idle,idle-light}.png`, `soft-body-motion.gif`, and `idle-rotation-hover.gif`. These are production RealityKit captures, not AI mockups or desktop automation. Reflections are simulated; the app does not sample or refract the desktop behind its transparent window. Local packaging uses ad-hoc signing.
