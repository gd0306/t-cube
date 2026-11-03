/** Native window visibility and media changes are event driven; this renderer owns no timer or frame loop. */
const staticPreferences = [
    matchMedia('(prefers-reduced-motion: reduce)'),
    matchMedia('(prefers-reduced-transparency: reduce)'),
    matchMedia('(forced-colors: active)'),
];
let pageHidden = false;
function synchronize(): void {
    const visible = !document.hidden && !pageHidden;
    document.documentElement.dataset.visible = String(visible);
    document.documentElement.dataset.animate = String(visible && !staticPreferences.some(preference => preference.matches));
}
for (const preference of staticPreferences) preference.addEventListener('change', synchronize);
document.addEventListener('visibilitychange', synchronize);
window.addEventListener('pagehide', () => { pageHidden = true; synchronize(); });
window.addEventListener('pageshow', () => { pageHidden = false; synchronize(); });
synchronize();
