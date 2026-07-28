import Toybox.Lang;
import Toybox.WatchUi;

class gsensrosDelegate extends WatchUi.BehaviorDelegate {

    var view as gsensrosView;

    function initialize(view as gsensrosView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() as Boolean {
        return view.onSelect();
    }

    function onBack() as Boolean {
        return view.onBack();
    }

    // Menu key on some devices – same POI action
    function onMenu() as Boolean {
        return view.onMenu();
    }

    // Instinct 2 / 2X: upper-left CTRL / Light button → KEY_LIGHT
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_LIGHT) {
            return view.onMenu();   // mark POI while recording
        }
        return false;              // leave other keys to the system
    }

    function onNextPage() as Boolean {
        view.scrollY -= view.SCROLL_STEP;   // DOWN button usually moves content up
        if (view.scrollY < view.SCROLL_MIN) {
            view.scrollY = view.SCROLL_MIN;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        view.scrollY += view.SCROLL_STEP;   // UP button usually moves content down
        if (view.scrollY > view.SCROLL_MAX) {
            view.scrollY = view.SCROLL_MAX;
        }
        WatchUi.requestUpdate();
        return true;
    }
}