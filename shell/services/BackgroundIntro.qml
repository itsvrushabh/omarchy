import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Keep startup and theme covers alive across background service handoffs.
Item {
  id: root

  property var host: null
  property bool cover: true
  readonly property bool sessionConsumed: String(sessionMarker.text() || "").trim() === (Quickshell.env("OMARCHY_SESSION_ID") || Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
  property bool startupSettled: sessionConsumed
  property bool startupPending: !sessionConsumed
  property bool startupMediaReady: false
  property real startupOpacity: startupPending ? 1 : 0
  readonly property bool desktopReady: !host || (!host.pluginReloading && (!host.pluginRegistry || !host.pluginRegistry.scanning) && (!("bar" in host) || !!host.bar))
  property bool checked: false
  property string themeToken: ""
  property string transitionToken: ""
  property bool fallbackPending: false
  property int framePollFailures: 0
  readonly property string startupBackgroundPath: Quickshell.env("OMARCHY_STARTUP_BACKGROUND")
  property string themeBackground: sessionConsumed && !Util.isVideoPath(startupBackgroundPath) ? startupBackgroundPath : ""
  property var themeNativeSize: null
  property string themeColors: ""
  property string themeShell: ""
  property real themeOpacity: 1
  readonly property var backgroundService: host && host.services ? host.firstPartyServiceFor("omarchy.background") : null
  readonly property bool backgroundActive: !!backgroundService && !backgroundService.suspended
  readonly property bool backgroundReady: backgroundActive && backgroundService.ready !== false

  function restoreStartupCursor() {
    Quickshell.execDetached(["hyprctl", "eval", "if omarchy_startup_cursor_restore then omarchy_startup_cursor_restore() end"])
  }

  function finishStartup() {
    if (!cover || !startupSettled) return
    var registry = host ? host.pluginRegistry : null
    var backgroundId = registry ? registry.resolveEnabledId("omarchy.background") : ""
    var disabled = registry && registry.installedPlugins[backgroundId] && !registry.isEnabled(backgroundId)
    if (!backgroundReady && !disabled) return
    cover = false
    if (!themeToken) themeBackground = ""
    startupMediaReady = true
    revealStartup()
  }

  function revealStartup() {
    if (!startupPending || startupFade.running || !startupMediaReady || !desktopReady) return
    if (!startupCovers.instances.length) return
    for (var panel of startupCovers.instances)
      if (panel.readyFrames < 2) return
    startupFade.start()
  }

  onDesktopReadyChanged: revealStartup()
  onBackgroundReadyChanged: {
    finishStartup()
    if (fallbackPending && backgroundReady) {
      fallbackPending = false
      fallbackTimeout.stop()
      revealTheme()
    }
  }
  Connections {
    target: root.host && root.host.pluginRegistry ? root.host.pluginRegistry : null
    function onPluginsChanged() { root.finishStartup() }
  }

  function prepareTheme(fromPath, token, colors, shell) {
    framePoll.stop()
    themeFade.stop()
    playbackFallback.stop()
    fallbackTimeout.stop()
    fallbackPending = false
    framePollFailures = 0
    themeToken = token
    transitionToken = token
    if (themeBackground !== fromPath) {
      themeNativeSize = backgroundService && backgroundService.nativeSizes ? backgroundService.nativeSizes[backgroundService.displayedBackground] : null
    }
    themeBackground = fromPath
    themeColors = colors
    themeShell = shell
    themeOpacity = 1
    themeFallback.restart()
    if (!backgroundActive && checked) {
      framePoll.start()
      if (!frameStatus.running) frameStatus.running = true
      playbackFallback.restart()
    }
  }

  function fallbackTheme() {
    if (!themeToken && !cover) return
    framePoll.stop()
    themeFallback.stop()
    playbackFallback.stop()
    framePollFailures = 0
    var bg = Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    Quickshell.execDetached(["omarchy-shell", "background", "setInstant", bg])
    if (backgroundService) {
      backgroundService.suspended = false
      if (typeof backgroundService.setInstant === "function") {
        backgroundService.setInstant(bg)
      } else if (typeof backgroundService.setBackground === "function") {
        backgroundService.setBackground(bg, true)
      }
    }
    if (backgroundReady || !backgroundService) {
      revealTheme()
      return
    }
    fallbackPending = true
    fallbackTimeout.restart()
  }

  function revealTheme() {
    if (!themeToken && !cover) return
    framePoll.stop()
    themeFallback.stop()
    playbackFallback.stop()
    fallbackTimeout.stop()
    fallbackPending = false
    framePollFailures = 0
    if (themeToken) {
      Commons.Color.loadColors(Util.decodeBase64(themeColors))
      Commons.Color.loadShell(Util.decodeBase64(themeShell))
      Style.scheduleRefresh()
    }
    cover = false
    themeToken = ""
    themeColors = ""
    themeShell = ""
    if (startupPending) {
      // The login reveal starts on moving video, without showing its final still.
      themeBackground = ""
      startupMediaReady = true
      revealStartup()
    } else {
      themeFade.restart()
    }
  }

  function finishTheme(token) {
    if (token === themeToken) {
      if (fallbackPending) return
      revealTheme()
    }
  }

  function themeStatus(token) {
    return token === transitionToken && (themeToken || fallbackPending || themeFade.running || startupFade.running) ? "pending" : "ready"
  }

  function themeCoverStatus(token) {
    if (token !== themeToken) return "superseded"
    if (!themeBackground) return "ready"
    for (var panel of covers.instances) {
      if (panel.coverFailed) return "error"
      if (!panel.coverReady) return "loading"
    }
    return covers.instances.length > 0 ? "ready" : "loading"
  }

  function cancelTheme() {
    framePoll.stop()
    themeFallback.stop()
    playbackFallback.stop()
    fallbackTimeout.stop()
    fallbackPending = false
    themeFade.stop()
    framePollFailures = 0
    themeToken = ""
    transitionToken = ""
    themeBackground = ""
    themeColors = ""
    themeShell = ""
  }

  NumberAnimation {
    id: startupFade
    target: root
    property: "startupOpacity"
    to: 0
    duration: Style.duration(420)
    easing.type: Easing.OutCubic
    onStarted: root.restoreStartupCursor()
    onFinished: root.startupPending = false
  }

  // A missing wallpaper or failed plugin must not leave applications hidden.
  Timer {
    interval: 10000
    running: root.startupPending
    onTriggered: {
      root.cover = false
      if (!root.themeToken) root.themeBackground = ""
      root.startupMediaReady = true
      startupFade.start()
    }
  }

  NumberAnimation {
    id: themeFade
    target: root
    property: "themeOpacity"
    to: 0
    duration: Style.duration(420)
    easing.type: Easing.OutCubic
    onFinished: root.themeBackground = ""
  }

  Timer {
    id: themeFallback
    interval: 10000
    onTriggered: root.fallbackTheme()
  }

  Timer {
    id: playbackFallback
    interval: 2500
    onTriggered: root.fallbackTheme()
  }

  Timer {
    id: fallbackTimeout
    interval: 2500
    onTriggered: {
      if (root.fallbackPending) {
        root.fallbackPending = false
        root.revealTheme()
      }
    }
  }

  // A renderer left over from another intro can first fade from its still.
  // Keep that preparation hidden until the actual video is fully revealed.
  Timer {
    id: framePoll
    interval: 16
    repeat: true
    onTriggered: if (!frameStatus.running) frameStatus.running = true
  }

  Process {
    id: frameStatus
    command: ["owe", "render-status"]
    property string token: ""
    onStarted: token = root.themeToken
    stdout: StdioCollector { id: frameStatusOut }
    onExited: function(exitCode) {
      if (token !== root.themeToken || (!token && !root.cover)) return
      if (exitCode !== 0) {
        root.framePollFailures += 1
        if (root.framePollFailures >= 20) root.fallbackTheme()
        return
      }
      root.framePollFailures = 0
      try {
        var status = JSON.parse(frameStatusOut.text)
        if (status.kind === "video" && status.ready && !status.has_transition && status.time_pos > 0) {
          playbackFallback.stop()
          root.revealTheme()
        } else if (status.error || (status.ready && status.kind && status.kind !== "video")) {
          root.fallbackTheme()
        }
      } catch (e) {}
    }
  }

  // A shell restart shares this compositor session; a new login does not.
  FileView {
    id: sessionMarker
    path: Quickshell.env("HOME") + "/.local/state/omarchy/background-intro.session-id"
    blockLoading: true
    watchChanges: false
    printErrors: false
  }

  Process {
    id: startupBackground
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector { id: startupBackgroundOut }
    onExited: function(exitCode) {
      var path = String(startupBackgroundOut.text || "").trim()
      if (exitCode === 0 && root.cover && !root.startupPending && !root.themeToken && !Util.isVideoPath(path))
        root.themeBackground = path
    }
  }

  Component.onCompleted: {
    checked = true
    if (sessionConsumed) restoreStartupCursor()
    if (!startupBackgroundPath && !startupPending) startupBackground.running = true
    introProc.running = true
  }

  Component.onDestruction: if (startupPending) restoreStartupCursor()

  onBackgroundActiveChanged: {
    if (!backgroundActive && checked) {
      if (cover || themeToken) {
        framePoll.start()
        if (!frameStatus.running) frameStatus.running = true
        playbackFallback.restart()
      }
    }
  }

  // Cover the bar as well as the wallpaper on a new login. Shell restarts
  // retain the current desktop and never map this startup cover.
  Variants {
    id: startupCovers
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      property int readyFrames: 0
      screen: modelData
      visible: root.startupPending
      color: "transparent"
      mask: Region {}
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "omarchy-background"

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.startupOpacity
      }

      FrameAnimation {
        running: root.startupPending && root.desktopReady && readyFrames < 2
        onTriggered: {
          readyFrames += 1
          if (readyFrames === 2) root.revealStartup()
        }
      }
    }
  }

  Variants {
    id: covers
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      property int coverFrames: 0
      readonly property bool coverReady: outgoingFrame.status === Image.Ready && coverFrames >= 2
      readonly property bool coverFailed: outgoingFrame.status === Image.Error
      screen: modelData
      visible: (!root.startupPending && root.cover) || root.themeBackground !== "" || root.fallbackPending
      // Keep the window transparent throughout the fade. Paint the startup
      // color inside it so changing the window format cannot flash black.
      color: "transparent"
      mask: Region {}
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "omarchy-background"

      Rectangle {
        anchors.fill: parent
        visible: root.cover || (root.fallbackPending && (!root.themeBackground || panel.coverFailed))
        color: Commons.Color.background
      }

      Image {
        id: outgoingFrame
        anchors.fill: parent
        source: root.themeBackground ? Util.fileUrl(root.themeBackground) : ""
        sourceSize: {
          var w = Math.ceil((parent.width || modelData.width) * modelData.devicePixelRatio)
          var h = Math.ceil((parent.height || modelData.height) * modelData.devicePixelRatio)
          var native = root.themeNativeSize
          return native && (native.width < w || native.height < h) ? Qt.size(native.width, native.height) : Qt.size(w, h)
        }
        fillMode: Image.PreserveAspectCrop
        opacity: root.themeOpacity
        asynchronous: true
        onStatusChanged: {
          panel.coverFrames = 0
          if (status === Image.Error && root.themeToken) {
            root.fallbackTheme()
          }
        }
      }

      // Give the ready image a frame to reach the compositor before OWE
      // releases the shell's wallpaper underneath this cover.
      FrameAnimation {
        running: outgoingFrame.status === Image.Ready && panel.coverFrames < 2
        onTriggered: panel.coverFrames += 1
      }
    }
  }

  Process {
    id: introProc
    command: ["omarchy-theme-bg-boot-intro"]
    onExited: {
      root.startupSettled = true
      root.finishStartup()
    }
  }
}
