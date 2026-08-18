// VoxType Theme Reveal Overlay
//
// Drop this as a sibling overlay anchored to fill the visual root of a
// surface (the capsule / card Item, including any halo/glow padding) to
// get an Omarchy-style masked reveal transition whenever Theme commits
// a real (de-duplicated) palette change.
//
// Usage:
//   Item {
//       id: capsule
//       // ... pill / card contents ...
//   }
//   ThemeReveal { target: capsule }
//
// The component is a no-op (never holds the commit, never animates) when
// Theme.transitionStyle is "fade" or "none", or when the target isn't
// currently visible/mapped on screen (grabToImage requires a mapped
// window) — in those cases Theme simply commits the new colours instantly.

import QtQuick
import QtQuick.Window
import QtQuick.Effects

Item {
    id: reveal

    /// Visual root to snapshot and reveal. Should include any glow/halo
    /// padding that extends past the item's own content rect, since
    /// grabToImage only captures the item's bounding rectangle.
    required property Item target

    /// Reveal geometry: "omarchy" | "grow" | "wipe-right" | "wipe-left".
    /// ("fade" / "none" are handled by skipping the reveal entirely.)
    property string style: Theme.transitionStyle

    /// Reveal progress, 0 (fully old) .. 1 (fully new).
    property real progress: 1.0

    /// True while a reveal animation is in flight (snapshot + live view visible).
    readonly property bool active: progress < 1.0

    // Internal bookkeeping.
    property bool _holding: false
    property int _generation: 0

    anchors.fill: target
    z: target.z + 1

    // Purely a visual overlay — never intercepts input; the live view below
    // uses hideSource so the real target keeps receiving events normally.
    enabled: false

    Connections {
        target: Theme
        function onThemeAboutToChange() {
            reveal._handleAboutToChange();
        }
    }

    function _handleAboutToChange() {
        // Abort any in-flight reveal cleanly first, regardless of whether
        // this particular change ends up animated — a stale snapshot must
        // never be left showing.
        if (reveal._holding) {
            reveal._holding = false;
            anim.stop();
            reveal.progress = 1.0;
            Theme.releaseCommit();
        }

        if (reveal.style === "fade" || reveal.style === "none") {
            return;
        }

        const win = reveal.target ? reveal.target.Window.window : null;
        if (!win || !win.visible || !reveal.target.visible || reveal.target.opacity < 0.01) {
            // Not mapped / not meaningfully visible: let Theme commit instantly.
            return;
        }

        const gen = ++reveal._generation;
        Theme.holdCommit();
        reveal._holding = true;

        const queued = reveal.target.grabToImage(function (result) {
            if (gen !== reveal._generation) {
                // Superseded by a later theme change; ignore this callback.
                return;
            }
            reveal._holding = false;
            if (!result) {
                Theme.releaseCommit();
                return;
            }
            snapshot.source = result.url;
            reveal.progress = 0.0;
            // Release now: colours flip to the new theme immediately, and
            // the live view (sourced from the now-recoloured target) is
            // only shown through the growing mask, so this reads as a
            // clean reveal rather than an abrupt flip.
            Theme.releaseCommit();
            anim.restart();
        });

        if (!queued) {
            reveal._holding = false;
            Theme.releaseCommit();
        }
    }

    SequentialAnimation {
        id: anim
        PauseAnimation { duration: Theme.transitionDelayMs }
        NumberAnimation {
            target: reveal
            property: "progress"
            from: 0.0
            to: 1.0
            duration: Theme.transitionDurationMs
            easing.type: Easing.InOutCubic
        }
    }

    // Live ("new theme") view of the target, shown only inside the
    // growing mask region. hideSource keeps the real target rendering
    // normally (and interactive) everywhere else.
    ShaderEffectSource {
        id: liveView
        anchors.fill: parent
        sourceItem: reveal.target
        live: true
        visible: reveal.active
        hideSource: reveal.active
        layer.enabled: reveal.active
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.02
        }
    }

    // Frozen ("old theme") snapshot, shown only outside the growing mask
    // region (inverted mask), so the two layers never double-draw the
    // same pixel (important for the translucent glass background).
    Image {
        id: snapshot
        anchors.fill: parent
        cache: false
        asynchronous: false
        visible: reveal.active
        layer.enabled: reveal.active
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.02
        }
    }

    // Mask geometry: white = revealed (new theme / live view), transparent
    // = still showing the frozen snapshot. Rendered off-screen (visible:
    // false, layer.enabled: true) purely to be sampled as maskSource.
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real reach: Math.hypot(parent.width, parent.height) / 2 + 4

        // "grow": circular reveal expanding from the centre.
        Rectangle {
            visible: reveal.style === "grow"
            anchors.centerIn: parent
            color: "white"
            width: 2 * mask.reach * reveal.progress
            height: width
            radius: width / 2
        }

        // "omarchy": slanted band growing symmetrically from the centre,
        // matching Omarchy's own wallpaper reveal transition.
        Rectangle {
            visible: reveal.style === "omarchy"
            color: "white"
            anchors.centerIn: parent
            height: parent.height * 2
            width: (parent.width + parent.height) * reveal.progress
            rotation: -10
        }

        // "wipe-right" / "wipe-left": directional horizontal wipe.
        Rectangle {
            visible: reveal.style.indexOf("wipe") === 0
            color: "white"
            anchors.top: parent.top
            height: parent.height
            width: parent.width * reveal.progress
            x: reveal.style === "wipe-left" ? parent.width - width : 0
        }
    }
}
