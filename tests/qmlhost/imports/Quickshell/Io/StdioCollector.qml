import QtQuick
QtObject {
    property string fixtureText: ""
    readonly property string text: fixtureText
    readonly property string data: fixtureText
    property bool waitForEnd: true
    signal streamFinished()
    function fixtureBegin() { fixtureText = ""; }
    function fixtureFinish(value) { fixtureText = value; streamFinished(); }
}
