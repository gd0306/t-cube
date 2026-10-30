# Memory resource optimization

**Goal:** Reduce unnecessary image/texture allocation without changing visuals, hit testing, configuration or drafts. User approved directly implementing the preceding memory audit recommendations.

- [x] macOS: retain 1024 face layout precision; reuse unchanged face textures and update changed slot contents only, avoid icon work for appearance/group-name-only changes. Test material texture identity and replaced/removed targets.
- [x] macOS: release obsolete frozen frames when returning to live rendering; prepare theme blend endpoints once per transition and reuse bounded working resources without breaking premultiplied transparency. Test image lifetime, cancellation and existing pixel bounds.
- [x] Windows: bound/prune installed-app discovery NativeImage cache and redundant serialized icon cache, preserve active launcher icons and behavior. Test eviction/reload and discovery refresh.
- [x] Run controlled isolated before/after memory workload, full native/core tests and Windows checks; review, version build and install on maintainer Mac with application/raw JSON backup.

Do not change user configuration for performance experiments. Keep benchmark fixtures in temporary stores. Do not claim the current 14-hour process footprint vs a fresh process as an optimization gain. Preserve visual resolution this round. New architecture/render engine changes and automatic destruction of draft-bearing windows are out of scope until measurements justify them.
