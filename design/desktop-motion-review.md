# Desktop motion polish — 2026-09-17

## Implemented

- Mute buttons update their binding immediately. Slash progress derives from that binding, including an initially muted state and external updates. Rapid clicks cannot schedule stale unmute callbacks.
- Typing dots use one cancellable 240 ms sequence with 160 ms feedback and a 2-point displacement. Reduced motion leaves static dots; disappearing views cancel the sequence.
- Ringing pulses use a visible-only timeline capped at 30 Hz, with a static reduced-motion state. No repeat-forever animation remains in the call state transaction.
- Command-K toggles the switcher immediately.
- Login/signup transitions use the shared 240 ms screen token and honor reduced motion.
- Logo hover uses the existing 160 ms popover token. The legacy splash logo renders its completed state under reduced motion.
- The root transaction suppresses remaining legacy explicit and implicit animations when reduced motion is enabled.

## Verification and limits

The complete app passed Swift type-check for arm64 Mac Catalyst using Xcode 27. Three existing warnings remain in MatrixStore.swift. Git whitespace checks passed. Xcode build/test execution is blocked by an unaccepted Xcode license (exit 69). Runtime motion, frame pacing, focus behavior, and visual parity have not been validated for this change.

The 30 SVG icons were created and visually checked in Figma, then saved under design/icons. They are not integrated into runtime controls yet.

## Remaining review

- Inspect runtime menus, settings, profile, search, pinned messages, and thread transitions, including interruption and Escape dismissal.
- Check message hover actions for text reflow and positioning before changing their layout.
- Review old call demo timers separately; this patch does not turn simulated calling into real calling.
- Compare screenshots at the user's actual desktop window size. Preserve approved layout metrics until runtime comparison provides evidence for a change.
- Review remaining per-view animation literals against shared tokens; do not mechanically animate frequent navigation.

## Manual feel-check after build access returns

1. Toggle mute rapidly ten times, then navigate away and back. The slash must always match the state.
2. Start/stop typing repeatedly. Dots must stop after the typing indicator disappears.
3. Enable reduced motion while typing or ringing. Movement must cease immediately.
4. Open Command-K repeatedly and confirm that navigation has no animation delay.
5. Switch login/signup and open/close panels while their transition is still running; verify interruption and focus retention.
