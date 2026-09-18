#!/usr/bin/env bash

set -e

PLASMOID_ID="org.kde.roflo.mediaplayer"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"

# Протестировано на:
#   Arch Linux
#   KDE Plasma 6.7.5
#   KDE Frameworks 6.30.0
#   Qt 6.11.2
#   Kernel 7.2.6-zen2-1-zen
#   Wayland
#   Intel Core i5-11400F / NVIDIA GeForce GTX 1650 / 32 GiB RAM

mkdir -p "$PLASMOID_DIR/contents/ui"
mkdir -p "$PLASMOID_DIR/contents/config"

cat << 'EOF' > "$PLASMOID_DIR/contents/ui/main.qml"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation

    Plasmoid.backgroundHints: Plasmoid.NoBackground

    property string trackTitle: "Музыка не играет"
    property string trackArtist: "Включи плеер"
    property string artUrl: ""
    property string status: "Stopped"
    property string positionStr: "0:00"
    property string lengthStr: "0:00"
    property real progress: 0.0
    property real totalSec: 0.0
    property real currentSec: 0.0
    property real waveOffset: 0.0

    property color auraColor1: "#3b82f6"
    property color auraColor2: "#8b5cf6"

    readonly property string getMediaCmd: `bash -c '
        P=$(playerctl -l 2>/dev/null | head -n 1)
        if [ -z "$P" ]; then
            echo "Stopped|Музыка не играет|Включи плеер||0|0"
            exit 0
        fi

        STATUS=$(playerctl -p "$P" status 2>/dev/null || echo "Stopped")
        ART=$(playerctl -p "$P" metadata mpris:artUrl 2>/dev/null || echo "")
        TITLE=$(playerctl -p "$P" metadata xesam:title 2>/dev/null || playerctl -p "$P" metadata title 2>/dev/null || echo "Музыка не играет")
        ARTIST=$(playerctl -p "$P" metadata xesam:artist 2>/dev/null || playerctl -p "$P" metadata artist 2>/dev/null || echo "Включи плеер")
        POS=$(playerctl -p "$P" position 2>/dev/null || echo "0")
        LEN=$(playerctl -p "$P" metadata mpris:length 2>/dev/null || echo "0")

        echo "$STATUS|$TITLE|$ARTIST|$ART|$POS|$LEN"
    '`

    Plasma5Support.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var stdout = data["stdout"]

            if (stdout) {
                var parts = stdout.trim().split("|")

                if (parts.length >= 6) {
                    root.status = parts[0].trim()
                    root.trackTitle = parts[1].trim() || "Без названия"
                    root.trackArtist = parts[2].trim() || "Неизвестный исполнитель"
                    root.artUrl = parts[3].trim()

                    var posSec = Math.floor(parseFloat(parts[4]) || 0)
                    var lenSec = Math.floor((parseFloat(parts[5]) || 0) / 1000000)

                    root.totalSec = lenSec
                    root.currentSec = posSec
                    root.positionStr = formatTime(posSec)
                    root.lengthStr = formatTime(lenSec)

                    root.updateProgress()
                }
            }

            disconnectSource(sourceName)
        }

        function fetchMedia() {
            disconnectSource(root.getMediaCmd)
            connectSource(root.getMediaCmd)
        }

        function runControl(cmd) {
            if (cmd === "play-pause") {
                root.status =
                    (root.status === "Playing" ? "Paused" : "Playing")

                connectSource(
                    "bash -c 'P=$(playerctl -l 2>/dev/null \vert{} head -n 1); playerctl -p \"$P\" play-pause'"
                )

            } else if (cmd === "force-previous") {

                connectSource(
                    "bash -c 'P=$(playerctl -l 2>/dev/null | head -n 1); playerctl -p \"$P\" previous; sleep 0.05; playerctl -p \"$P\" previous'"
                )

            } else {

                connectSource(
                    "bash -c 'P=$(playerctl -l 2>/dev/null \vert{} head -n 1); playerctl -p \"$P\" " + cmd + "'"
                )
            }

            delayedFetch.restart()
        }

        function seekTo(targetSec) {
            root.currentSec = targetSec
            root.updateProgress()

            connectSource(
                "bash -c 'P=$(playerctl -l 2>/dev/null \vert{} head -n 1); playerctl -p \"$P\" position " + targetSec + "'"
            )

            delayedFetch.restart()
        }
    }

    Timer {
        id: delayedFetch
        interval: 300
        repeat: false

        onTriggered: executableSource.fetchMedia()
    }

    function formatTime(sec) {
        var m = Math.floor(sec / 60)
        var s = Math.floor(sec % 60)

        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function updateProgress() {
        if (totalSec > 0) {
            progress = Math.min(
                1.0,
                Math.max(0.0, currentSec / totalSec)
            )
        } else {
            progress = 0
        }

        positionStr = formatTime(currentSec)
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: executableSource.fetchMedia()
    }

    Timer {
        interval: 1000
        running: root.status === "Playing"
        repeat: true

        onTriggered: {
            if (root.currentSec < root.totalSec) {
                root.currentSec += 1
                root.updateProgress()
            }
        }
    }

    NumberAnimation on waveOffset {
        running: root.status === "Playing"
        from: 0
        to: Math.PI * 2
        duration: 1500
        loops: Animation.Infinite
    }

    fullRepresentation: Item {
        implicitWidth: 280
        implicitHeight: 380

        Rectangle {
            id: mainBg
            anchors.fill: parent
            color: Qt.rgba(0.1, 0.1, 0.12, 0.9)
            radius: 20
            clip: true

            Item {
                id: auraContainer
                anchors.fill: parent
                opacity: 0.7

                Rectangle {
                    width: parent.width * 1.6
                    height: width
                    radius: width / 2

                    anchors.horizontalCenter: parent.left
                    anchors.verticalCenter: parent.top

                    color: root.auraColor1

                    Behavior on color {
                        ColorAnimation {
                            duration: 800
                        }
                    }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: 40
                            duration: 8000
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: -30
                            duration: 9000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: 50
                            duration: 10000
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: -20
                            duration: 7000
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 1.6
                    height: width
                    radius: width / 2

                    anchors.horizontalCenter: parent.right
                    anchors.verticalCenter: parent.bottom

                    color: root.auraColor2

                    Behavior on color {
                        ColorAnimation {
                            duration: 800
                        }
                    }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: -50
                            duration: 9000
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: 20
                            duration: 8000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: -40
                            duration: 7500
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: 30
                            duration: 9500
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 1.4
                    height: width
                    radius: width / 2

                    anchors.horizontalCenter: parent.right
                    anchors.verticalCenter: parent.top

                    color: root.auraColor1

                    Behavior on color {
                        ColorAnimation {
                            duration: 800
                        }
                    }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: -30
                            duration: 8500
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: 40
                            duration: 10500
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true

                        PropertyAnimation {
                            to: 60
                            duration: 9000
                            easing.type: Easing.InOutSine
                        }

                        PropertyAnimation {
                            to: -30
                            duration: 8000
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            MultiEffect {
                anchors.fill: auraContainer
                source: auraContainer

                blurEnabled: true
                blur: 1.0
                blurMax: 96
            }

            Canvas {
                id: colorExtractor

                width: 30
                height: 30
                visible: false

                property string currentArt: root.artUrl

                onCurrentArtChanged: {
                    if (currentArt !== "") {
                        colorExtractor.loadImage(currentArt)
                    }
                }

                function ensureBrightness(r, g, b) {
                    var c = Qt.rgba(
                        r / 255,
                        g / 255,
                        b / 255,
                        1.0
                    )

                    var lightness =
                        (Math.max(r, g, b) +
                         Math.min(r, g, b)) / (2 * 255)

                    if (lightness < 0.35) {
                        var factor =
                            0.45 / Math.max(lightness, 0.05)

                        var nr = Math.min(1.0, c.r * factor)
                        var ng = Math.min(1.0, c.g * factor)
                        var nb = Math.min(1.0, c.b * factor)

                        return Qt.rgba(
                            nr,
                            ng,
                            nb,
                            1.0
                        )
                    }

                    return c
                }

                onImageLoaded: {
                    var ctx = getContext("2d")

                    ctx.drawImage(
                        currentArt,
                        0,
                        0,
                        width,
                        height
                    )

                    var p1 =
                        ctx.getImageData(
                            5,
                            5,
                            1,
                            1
                        ).data

                    var p2 =
                        ctx.getImageData(
                            25,
                            25,
                            1,
                            1
                        ).data

                    root.auraColor1 =
                        ensureBrightness(
                            p1[0],
                            p1[1],
                            p1[2]
                        )

                    root.auraColor2 =
                        ensureBrightness(
                            p2[0],
                            p2[1],
                            p2[2]
                        )
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                // Обложка
                Rectangle {
                    id: coverFrame

                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 200

                    radius: 16
                    color: Qt.rgba(0, 0, 0, 0.3)
                    clip: true

                    Image {
                        id: coverImage

                        anchors.fill: parent

                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop

                        visible:
                            root.artUrl !== "" &&
                            status === Image.Ready

                        asynchronous: true
                    }

                    PlasmaComponents.Label {
                        anchors.centerIn: parent

                        text: "🎵"
                        font.pixelSize: 48

                        visible:
                            root.artUrl === "" ||
                            coverImage.status !== Image.Ready
                    }
                }

                // Информация о треке
                Rectangle {
                    Layout.fillWidth: true

                    color: Qt.rgba(0, 0, 0, 0.4)

                    border.color:
                        Qt.rgba(1, 1, 1, 0.12)

                    border.width: 1
                    radius: 10

                    implicitHeight:
                        infoColumn.implicitHeight + 10

                    ColumnLayout {
                        id: infoColumn

                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 1

                        PlasmaComponents.Label {
                            text: root.trackTitle

                            font.pixelSize: 14
                            font.bold: true

                            color: "#ffffff"

                            horizontalAlignment:
                                Text.AlignHCenter

                            elide:
                                Text.ElideRight

                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: root.trackArtist

                            font.pixelSize: 11

                            color: "#b0b0b0"

                            horizontalAlignment:
                                Text.AlignHCenter

                            elide:
                                Text.ElideRight

                            Layout.fillWidth: true
                        }
                    }
                }

                // =========================================================
                // MATERIAL 3 EXPRESSIVE ПРОГРЕСС-БАР
                // =========================================================

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Item {
                        id: seekContainer

                        Layout.fillWidth: true
                        height: 28

                        // Основная стеклянная капсула
                        Rectangle {
                            id: seekPill

                            anchors.fill: parent

                            radius: height / 2

                            color: Qt.rgba(
                                1,
                                1,
                                1,
                                0.055
                            )

                            border.color:
                                Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.08
                                )

                            border.width: 1
                        }

                        // Левая декоративная "разделительная" черта
                        Rectangle {
                            id: leftSeparator

                            width: 2
                            height: 12
                            radius: 1

                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter

                            color:
                                Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.28
                                )
                        }

                        // Правая декоративная "разделительная" черта
                        Rectangle {
                            id: rightSeparator

                            width: 2
                            height: 12
                            radius: 1

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter

                            color:
                                Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.28
                                )
                        }

                        // Внутренняя область самой полосы
                        Item {
                            id: seekTrackArea

                            anchors.left: parent.left
                            anchors.right: parent.right

                            anchors.leftMargin: 20
                            anchors.rightMargin: 20

                            anchors.verticalCenter:
                                parent.verticalCenter

                            height: 18

                            // Неактивная часть
                            Rectangle {
                                id: seekBackground

                                anchors.left: parent.left
                                anchors.right: parent.right

                                anchors.verticalCenter:
                                    parent.verticalCenter

                                height: 6
                                radius: 3

                                color:
                                    Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.13
                                    )
                            }

                            // =================================================
                            // АКТИВНАЯ ЧАСТЬ — ИЗВИВАЮЩАЯСЯ ВОЛНА (Canvas)
                            // =================================================
                            Item {
                                id: seekActiveContainer

                                anchors.left:
                                    seekBackground.left

                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                width:
                                    seekBackground.width *
                                    root.progress

                                height: 18

                                clip: true

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type:
                                            Easing.OutCubic
                                    }
                                }

                                Canvas {
                                    id: waveCanvas

                                    anchors.fill: parent

                                    property real stripHeight: 6
                                    property real amplitude: 3.5
                                    property real wavelength: 22
                                    property real phase: root.waveOffset

                                    onPhaseChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()

                                        var w = width
                                        var h = height
                                        var cy = h / 2

                                        if (w <= 0)
                                            return

                                        var grad = ctx.createLinearGradient(
                                            0, 0, w, 0
                                        )
                                        grad.addColorStop(
                                            0.0,
                                            root.auraColor1
                                        )
                                        grad.addColorStop(
                                            0.55,
                                            Qt.lighter(
                                                root.auraColor1,
                                                1.15
                                            )
                                        )
                                        grad.addColorStop(
                                            1.0,
                                            root.auraColor2
                                        )

                                        ctx.fillStyle = grad
                                        ctx.strokeStyle = grad
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"

                                        ctx.beginPath()

                                        var steps = Math.max(
                                            2,
                                            Math.ceil(w / 2)
                                        )

                                        for (var i = 0; i <= steps; i++) {
                                            var x = (i / steps) * w
                                            var y = cy
                                                - root.waveAmplitudeAt(
                                                    x,
                                                    phase,
                                                    wavelength,
                                                    amplitude
                                                )

                                            if (i === 0)
                                                ctx.moveTo(x, y)
                                            else
                                                ctx.lineTo(x, y)
                                        }

                                        for (var j = steps; j >= 0; j--) {
                                            var x2 = (j / steps) * w
                                            var y2 = cy
                                                + root.waveAmplitudeAt(
                                                    x2,
                                                    phase,
                                                    wavelength,
                                                    amplitude
                                                )

                                            ctx.lineTo(x2, y2)
                                        }

                                        ctx.closePath()
                                        ctx.fill()
                                    }
                                }

                                MultiEffect {
                                    anchors.fill: waveCanvas

                                    source: waveCanvas

                                    blurEnabled: true
                                    blur: 0.6
                                    blurMax: 18

                                    opacity: 0.6
                                }
                            }

                            // Маленькие Material-разделители внутри трека
                            Rectangle {
                                width: 1
                                height: 5
                                radius: 1

                                x: seekBackground.width * 0.25
                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                color:
                                    Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.16
                                    )
                            }

                            Rectangle {
                                width: 1
                                height: 5
                                radius: 1

                                x: seekBackground.width * 0.50
                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                color:
                                    Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.16
                                    )
                            }

                            Rectangle {
                                width: 1
                                height: 5
                                radius: 1

                                x: seekBackground.width * 0.75
                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                color:
                                    Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.16
                                    )
                            }

                            // =================================================
                            // СВЕТЯЩАЯСЯ ВЕРТИКАЛЬНАЯ ПОЛОСКА-БЕГУНОК
                            // =================================================

                            Rectangle {
                                id: seekThumbGlow

                                width: 14
                                height: 22
                                radius: 7

                                x:
                                    Math.max(
                                        -7,
                                        Math.min(
                                            seekBackground.width - 7,
                                            seekBackground.width *
                                            root.progress - 7
                                        )
                                    )

                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                color:
                                    root.auraColor2

                                opacity:
                                    seekMouse.containsMouse ||
                                    seekMouse.pressed
                                    ? 0.32
                                    : 0.18

                                scale:
                                    seekMouse.containsMouse
                                    ? 1.15
                                    : 1.0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }

                                Behavior on scale {
                                    SpringAnimation {
                                        spring: 4.5
                                        damping: 0.35
                                    }
                                }
                            }

                            MultiEffect {
                                anchors.fill:
                                    seekThumbGlow

                                source:
                                    seekThumbGlow

                                blurEnabled: true
                                blur: 1.0
                                blurMax: 20

                                opacity: 0.8
                            }

                            Rectangle {
                                id: seekThumb

                                width: 8
                                height: 18
                                radius: 4

                                x:
                                    Math.max(
                                        -4,
                                        Math.min(
                                            seekBackground.width - 4,
                                            seekBackground.width *
                                            root.progress - 4
                                        )
                                    )

                                anchors.verticalCenter:
                                    seekBackground.verticalCenter

                                color: "#ffffff"

                                border.color:
                                    Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.45
                                    )

                                border.width: 1

                                scale:
                                    seekMouse.containsMouse ||
                                    seekMouse.pressed
                                    ? 1.18
                                    : 1.0

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type:
                                            Easing.OutCubic
                                    }
                                }

                                Behavior on scale {
                                    SpringAnimation {
                                        spring: 5
                                        damping: 0.35
                                    }
                                }
                            }
                        }

                        // Область управления
                        MouseArea {
                            id: seekMouse

                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked: (mouse) => {
                                handleSeek(mouse.x)
                            }

                            onPositionChanged: (mouse) => {
                                if (pressed) {
                                    handleSeek(mouse.x)
                                }
                            }

                            function handleSeek(mouseX) {
                                if (root.totalSec > 0) {

                                    var trackStart =
                                        seekTrackArea.x

                                    var trackWidth =
                                        seekTrackArea.width

                                    var pct =
                                        (mouseX -
                                         trackStart) /
                                        trackWidth

                                    pct =
                                        Math.max(
                                            0,
                                            Math.min(
                                                1,
                                                pct
                                            )
                                        )

                                    var targetSec =
                                        Math.floor(
                                            pct *
                                            root.totalSec
                                        )

                                    executableSource.seekTo(
                                        targetSec
                                    )
                                }
                            }
                        }
                    }

                    // Время
                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: root.positionStr

                            font.pixelSize: 10
                            color: "#808080"
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: root.lengthStr

                            font.pixelSize: 10
                            color: "#808080"
                        }
                    }
                }

                // =========================================================
                // КНОПКИ УПРАВЛЕНИЯ
                // =========================================================

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16

                    Item {
                        Layout.fillWidth: true
                    }

                    // Кнопка Назад
                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46

                        Rectangle {
                            id: prevBtnBg

                            anchors.fill: parent

                            radius: 23

                            scale:
                                prevBtnMouse.pressed
                                ? 0.90
                                : (
                                    prevBtnMouse.containsMouse
                                    ? 1.08
                                    : 1.0
                                )

                            color:
                                prevBtnMouse.containsMouse
                                ? Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.25
                                )
                                : Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.12
                                )

                            border.color:
                                Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.25
                                )

                            border.width: 1

                            Behavior on scale {
                                SpringAnimation {
                                    spring: 4.5
                                    damping: 0.3
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        MultiEffect {
                            anchors.fill: prevBtnBg

                            source: auraContainer

                            blurEnabled: true
                            blur: 1.0
                            blurMax: 32

                            maskEnabled: true
                            maskSource: prevBtnBg
                        }

                        Text {
                            anchors.centerIn: parent

                            text: "⏮"

                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: prevBtnMouse

                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked:
                                executableSource.runControl(
                                    "force-previous"
                                )
                        }
                    }

                    // Кнопка Play/Pause
                    Item {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54

                        Rectangle {
                            id: playBtnBg

                            anchors.fill: parent

                            radius:
                                root.status === "Playing"
                                ? 27
                                : 16

                            scale:
                                playBtnMouse.pressed
                                ? 0.90
                                : (
                                    playBtnMouse.containsMouse
                                    ? 1.08
                                    : 1.0
                                )

                            color: {
                                if (root.status === "Playing") {

                                    return playBtnMouse.containsMouse
                                        ? Qt.rgba(
                                            1,
                                            1,
                                            1,
                                            0.35
                                        )
                                        : Qt.rgba(
                                            1,
                                            1,
                                            1,
                                            0.20
                                        )

                                } else {

                                    return playBtnMouse.containsMouse
                                        ? "#ffffff"
                                        : "#e0e0e0"
                                }
                            }

                            border.color:
                                root.status === "Playing"
                                ? Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.3
                                )
                                : "transparent"

                            border.width: 1

                            Behavior on radius {
                                SpringAnimation {
                                    spring: 3.5
                                    damping: 0.3
                                }
                            }

                            Behavior on scale {
                                SpringAnimation {
                                    spring: 4.5
                                    damping: 0.3
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        MultiEffect {
                            anchors.fill: playBtnBg

                            source: auraContainer

                            blurEnabled:
                                root.status === "Playing"

                            blur: 1.0
                            blurMax: 32

                            maskEnabled: true
                            maskSource: playBtnBg
                        }

                        Text {
                            anchors.centerIn: parent

                            text:
                                root.status === "Playing"
                                ? "⏸"
                                : "▶"

                            font.pixelSize: 18

                            color:
                                root.status === "Playing"
                                ? "#ffffff"
                                : "#000000"
                        }

                        MouseArea {
                            id: playBtnMouse

                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked:
                                executableSource.runControl(
                                    "play-pause"
                                )
                        }
                    }

                    // Кнопка Вперед
                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46

                        Rectangle {
                            id: nextBtnBg

                            anchors.fill: parent

                            radius: 23

                            scale:
                                nextBtnMouse.pressed
                                ? 0.90
                                : (
                                    nextBtnMouse.containsMouse
                                    ? 1.08
                                    : 1.0
                                )

                            color:
                                nextBtnMouse.containsMouse
                                ? Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.25
                                )
                                : Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.12
                                )

                            border.color:
                                Qt.rgba(
                                    1,
                                    1,
                                    1,
                                    0.25
                                )

                            border.width: 1

                            Behavior on scale {
                                SpringAnimation {
                                    spring: 4.5
                                    damping: 0.3
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        MultiEffect {
                            anchors.fill: nextBtnBg

                            source: auraContainer

                            blurEnabled: true
                            blur: 1.0
                            blurMax: 32

                            maskEnabled: true
                            maskSource: nextBtnBg
                        }

                        Text {
                            anchors.centerIn: parent

                            text: "⏭"

                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: nextBtnMouse

                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked:
                                executableSource.runControl(
                                    "next"
                                )
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    function waveAmplitudeAt(x, phase, wavelength, amplitude) {
        return Math.sin(
            (x / wavelength) * Math.PI * 2 + phase
        ) * amplitude
    }
}
EOF

cat << 'EOF' > "$PLASMOID_DIR/contents/config/main.xml"
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0 http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="backgroundHints" type="Enum">
      <default>0</default>
    </entry>
  </group>
</kcfg>
EOF

kbuildsycoca6 --noincremental &>/dev/null || true

echo ""
read -r -p "Restart plasmashell now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    nohup plasmashell --replace >/dev/null 2>&1 &
    sleep 1
fi

echo "Done"
