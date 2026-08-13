import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class gsensrosMenuDelegate extends WatchUi.MenuInputDelegate {

    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
        System.println("Menu delegate is not wired in this build");
    }

}