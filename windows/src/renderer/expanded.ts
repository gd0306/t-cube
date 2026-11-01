import { subscribe } from './util';
const container = document.querySelector<HTMLElement>('#icons')!;
const buttons = Array.from({ length: 4 }, () => {
    const button = document.createElement('button');
    const img = document.createElement('img');
    img.alt = '';
    const title = document.createElement('span');
    title.className = 'website-title';
    title.hidden = true;
    button.append(img, title);
    container.append(button);
    return button;
});
subscribe(({ state, icons }) => {
    const face = state.expandedFace;
    buttons.forEach((button, slot) => {
        const item = face ? state.configuration.groups[face].slots[slot] : null;
        button.disabled = !item;
        button.setAttribute('aria-label', item?.name ?? '空');
        const title = button.querySelector<HTMLElement>('.website-title')!;
        title.hidden = item?.kind !== 'website';
        title.textContent = item?.kind === 'website' ? item.name.replace(/\s+/gu, ' ').trim() : '';
        button.title = item?.kind === 'website' ? item.name : '';
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
