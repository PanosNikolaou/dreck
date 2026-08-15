import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class gsensrosDelegate extends WatchUi.BehaviorDelegate {

    var view as gsensrosView;
    var suppressNextSelect = false;
    var suppressUntilMs = 0;

    function initialize(view as gsensrosView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() as Boolean {
        var nowMs = System.getTimer();
        if (suppressNextSelect && nowMs < suppressUntilMs) {
            suppressNextSelect = false;
            return true;
        }
        return view.onSelect();
    }

    function onBack() as Boolean {
        return view.onBack();
    }

    // Menu key on some devices – same POI action
    function onMenu() as Boolean {
        suppressNextSelect = true;
        suppressUntilMs = System.getTimer() + 200;
        return view.handlePoiAction();
    }

    // Instinct 2 / 2X: use the UP button for POI marking
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_MENU) {
            suppressNextSelect = true;
            suppressUntilMs = System.getTimer() + 200;
            return view.handlePoiAction();   // mark POI while recording
        }
        return false;              // leave other keys to the system
    }

    var lastScrollRequestMs = 0;
    const SCROLL_REQUEST_THROTTLE_MS = 80;

    function onNextPage() as Boolean {
        var nowMs = System.getTimer();
        if ((nowMs - lastScrollRequestMs) >= SCROLL_REQUEST_THROTTLE_MS) {
            view.scrollY -= view.SCROLL_STEP;
            if (view.scrollY < view.SCROLL_MIN) {
                view.scrollY = view.SCROLL_MIN;
            }
            lastScrollRequestMs = nowMs;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        var nowMs = System.getTimer();
        if ((nowMs - lastScrollRequestMs) >= SCROLL_REQUEST_THROTTLE_MS) {
            view.scrollY += view.SCROLL_STEP;
            if (view.scrollY > view.SCROLL_MAX) {
                view.scrollY = view.SCROLL_MAX;
            }
            lastScrollRequestMs = nowMs;
            WatchUi.requestUpdate();
        }
        return true;
    }
}