export interface RenderActivity {
    visible: boolean; documentVisible: boolean; hovered: boolean; interacting: boolean;
    reducedMotion: boolean; autoRotates: boolean; idlePowerSaving: boolean;
    slimeActive: boolean; settling: boolean; glow: number; themeTransition?: boolean;
}
/** Zero means no animation timer; explicit changes still render one frame. */
export function animationCadence(activity: RenderActivity): 0 | 15 | 30 {
    if (!activity.visible || !activity.documentVisible || activity.reducedMotion) return 0;
    if (activity.interacting || activity.hovered || activity.slimeActive || activity.settling || activity.themeTransition) return 30;
    return !activity.idlePowerSaving && (activity.autoRotates || activity.glow > 0) ? 15 : 0;
}
