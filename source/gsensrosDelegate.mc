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