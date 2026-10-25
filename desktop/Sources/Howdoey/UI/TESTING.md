# UI manual test checklist

Status key: [ ] not run · [x] passed. **Nothing below has been run yet.**
Needs: Screen Recording + Accessibility granted, a provider configured, and (for the multi-display rows) two displays, ideally one Retina and one not.

## Selection
- [ ] Menu bar icon (or Control-Option-Space) opens the panel at the upper right of the display the mouse is on.
- [ ] "Select an area" hides the panel, tints every display, shows the pill and crosshair.
- [ ] Dragging draws an outline with a live W × H label; releasing selects. A drag under ~12 pt is ignored (no selection).
- [ ] The help button shows its popover and tooltip, and does not start a drag.
- [ ] "Select a window": hovering highlights the window under the pointer (never Howdoey's own); clicking selects it.
- [ ] After selecting, the panel returns with a thumbnail, "Helping with <app>", and a working clear (x) button.

## Escape
- [ ] Esc during area selection removes all overlays and restores the panel; nothing is captured.
- [ ] Esc during window selection does the same.
- [ ] Choosing Stop from elsewhere (menu bar) while selecting also removes the overlays.

## Multiple displays
- [ ] Overlays appear on every display; dragging on the secondary display selects the correct region (compare thumbnail to the area).
- [ ] A display arranged above/left of the primary (negative coordinates) still selects correctly.
- [ ] A drag cannot span two displays (it stays on the display where it began); the capture is the intended region only.

## Retina scaling
- [ ] On a Retina display, the thumbnail covers the same area that was outlined (not 2× offset or half size).
- [ ] Same check on a non-Retina display; the dimension label shows points, not pixels.

## Capture exclusion
- [ ] The thumbnail contains no tint, outline, pill, or W × H label.
- [ ] The Howdoey panel is not in the thumbnail unless it was inside the selected area on purpose.
- [ ] Show Me ring/caption are absent from any capture taken for "Check my progress".

## Approval
- [ ] Do It on a file move shows the exact source and destination paths, the app name, and Approve/Cancel.
- [ ] Cancel performs nothing and the file stays put.
- [ ] Approve calls the backend; the UI shows no "done" message until the backend's own message arrives.
- [ ] Name collision: approval shows the new destination name chosen by the backend.

## Show Me controls
- [ ] The ring and pseudo-cursor appear over the target, the real mouse does not move, and clicks pass through to the app underneath.
- [ ] The controls panel shows the step caption, "Check my progress" and Stop.
- [ ] "Check my progress" is enabled only while following a step; it shows a checking state, then the backend's result.
- [ ] No step advances without the user acting or tapping Check my progress (watch ~2 minutes idle).
- [ ] Stop removes ring, cursor and controls immediately.
- [ ] System Settings > Accessibility > Reduce motion: no pulsing or travel animation.

## Settings
- [ ] Permission rows match System Settings; buttons open the right pane.
- [ ] Provider, address, model and key save; the key field is empty again after reopening.
- [ ] "What gets sent" shows local vs. remote host correctly and the screenshot toggle changes its text.

## Known coordinator note
UIHost.install() is meant to own the four AppModel hooks. If AppCoordinator also assigns them, the last writer wins and one of the two overlay implementations will be unused.
