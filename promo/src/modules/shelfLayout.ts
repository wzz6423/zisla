export const SHELF_LAYOUT = {
  shareWidth: 84,
  columnGap: 6,
  gridTop: 91,
  itemWidth: 66,
  itemHeight: 84,
  pitchX: 74,
  pitchY: 92,
  menuWidth: 178,
  menuHeight: 141,
} as const;

type Point = {x: number; y: number};

export const shelfItemLayout = (index: number) => ({
  left: 4 + (index % 8) * SHELF_LAYOUT.pitchX,
  top: 7 + Math.floor(index / 8) * SHELF_LAYOUT.pitchY,
  width: SHELF_LAYOUT.itemWidth,
  height: SHELF_LAYOUT.itemHeight,
});

// Drag landing and the context-menu cursor share the file icon's actual position.
export const shelfItemPoint = (index: number): Point => {
  const item = shelfItemLayout(index);
  return {
    x: SHELF_LAYOUT.shareWidth + SHELF_LAYOUT.columnGap + 1 + item.left + item.width / 2,
    y: 1 + SHELF_LAYOUT.gridTop + item.top + 25,
  };
};

export const shelfMenuPlacement = (anchor: Point, viewport: {width: number; height: number}) => {
  const margin = 8;
  const flipX = anchor.x + SHELF_LAYOUT.menuWidth > viewport.width - margin;
  const flipY = anchor.y + SHELF_LAYOUT.menuHeight > viewport.height - margin;
  return {
    x: Math.max(margin, Math.min(viewport.width - SHELF_LAYOUT.menuWidth - margin, anchor.x - (flipX ? SHELF_LAYOUT.menuWidth : 0))),
    y: Math.max(margin, Math.min(viewport.height - SHELF_LAYOUT.menuHeight - margin, anchor.y - (flipY ? SHELF_LAYOUT.menuHeight : 0))),
    transformOrigin: `${flipY ? 'bottom' : 'top'} ${flipX ? 'right' : 'left'}`,
  };
};
