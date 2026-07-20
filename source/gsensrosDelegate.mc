import Toybox.Lang;
import Toybox.WatchUi;

class gsensrosDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Forward Select to the View
    function onSelect() as Boolean {
        System.println("Delegate: onSelect called");
        return false; // Let View handle it
    }
}