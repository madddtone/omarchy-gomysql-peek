import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "madddtone.gomysql-peek"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggle() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle " + root.moduleName)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf4c0"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "GoMySQL Peek — browse MySQL data"
    onPressed: root.toggle()
  }
}
