# Common-content templates verification

- Templates are explicitly enabled per item. Legacy records without the flag remain ordinary text. Repeated names are filled once; malformed and missing placeholders remain literal. Both platforms use the existing clipboard and focus-checked paste paths.
- `swift test --parallel --num-workers 1 --scratch-path .build/tests`: passed (80 native tests, 100 core tests). The standard concurrent run failed the rendering lifecycle snapshot test; the same test passed in isolation and in the single-worker full run. The later added malformed-placeholder test also passed in a focused run.
- `bash scripts/build-app.sh --debug`: passed with local signing.
- Windows: `npm run typecheck`, `npm test` (146 passed, one skipped), and `npm run build` passed using Node 22.19.0.
- The Windows renderer was exercised in Chrome against a local mock bridge: filling repeated variables updated the preview, legacy text copied without a fill prompt, and a simulated clipboard error retained the filled values. This is not a native Windows paste test.
- Added the template path to the existing isolated Windows native office smoke test; it requires Windows and was not executed on this macOS host. Native macOS template sheet and permission-dependent cross-application paste were not manually exercised.
