export const EDGE_VISIBILITY_CHANNEL = 'tcube:edge-visible';
export interface EdgeVisibilityBridge {
    onVisibility(callback:(visible:boolean)=>void):()=>void;
}
