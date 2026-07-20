import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class gsensrosApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new gsensrosView();
        return [ view, new gsensrosDelegate(view) ];
    }
}

function getApp() as gsensrosApp {
    return Application.getApp() as gsensrosApp;
}