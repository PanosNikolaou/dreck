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

    // Explicitly handle Back button
    function onBack() as Boolean {
        System.println("Delegate: onBack called");
        return view.onBack();
    }
}