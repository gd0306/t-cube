import { subscribe } from './util';
const container = document.querySelector<HTMLElement>('#icons')!;
const buttons = Array.from({ length: 4 }, () => {
    const button = document.createElement('button');
    const img = document.createElement('img');
    img.alt = '';
    button.append(img);
    container.append(button);
    return button;
});
subscribe(({ state, icons }) => {
    const face = state.expandedFace;
    buttons.forEach((button, slot) => {
        const item = face ? state.configuration.groups[face].slots[slot] : null;
        button.disabled = !item;
        button.setAttribute('aria-label', item?.name ?? '空');
        const img = button.querySelector('img')!;
        img.src = item ? (icons[item.id] ?? '') : '';
        button.onclick =
            item && face
                ? () => {
                      void window.tcube.launch({ face, slot });
                  }
                : null;
    });
});
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') void window.tcube.closeExpanded();
});
