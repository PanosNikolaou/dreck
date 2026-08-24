import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class gsensrosMenuDelegate extends WatchUi.MenuInputDelegate {

    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
        // intentionally silent by default; debug logging is controlled by app storage
    }

}