import QtQuick
import qs.Common

Item {
    id: root

    property string imagePath: ""
    property int maxCacheSize: 512
    property int status: isAnimated ? animatedImg.status : staticImg.status
    property int fillMode: Image.PreserveAspectCrop

    readonly property bool isRemoteUrl: imagePath.startsWith("http://") || imagePath.startsWith("https://")
    readonly property bool isAnimated: {
        if (!imagePath)
            return false;
        const lower = imagePath.toLowerCase();
        return lower.endsWith(".gif") || lower.endsWith(".webp");
    }
    readonly property string normalizedPath: {
        if (!imagePath)
            return "";
        if (isRemoteUrl)
            return imagePath;
        if (imagePath.startsWith("file://"))
            return imagePath.substring(7);
        return imagePath;
    }

    function djb2Hash(str) {
        if (!str)
            return "";
        let hash = 5381;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) + hash) + str.charCodeAt(i);
            hash = hash & 0x7FFFFFFF;
        }
        return hash.toString(16).padStart(8, '0');
    }

    readonly property string imageHash: normalizedPath ? djb2Hash(normalizedPath) : ""
    readonly property string cachePath: imageHash && !isRemoteUrl && !isAnimated ? `${Paths.stringify(Paths.imagecache)}/${imageHash}@${maxCacheSize}x${maxCacheSize}.png` : ""
    readonly property string encodedImagePath: {
        if (!normalizedPath)
            return "";
        if (isRemoteUrl)
            return normalizedPath;
        return "file://" + normalizedPath.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    AnimatedImage {
        id: animatedImg
        anchors.fill: parent
        visible: root.isAnimated
        asynchronous: true
        fillMode: root.fillMode
        source: root.isAnimated ? root.imagePath : ""
        playing: visible && status === AnimatedImage.Ready
    }

    // whether staticImg currently shows the cached thumbnail (vs the original).
    // Explicit state instead of comparing `source` to a string: a QML url never
    // strict-equals a string, which silently killed both the error fallback and
    // the cache save in the previous version.
    property bool _usingCache: false
    // one grab per image: without this, every visibility toggle while scrolling
    // would re-grab and re-save the same thumbnail
    property bool _cacheSaved: false

    Image {
        id: staticImg
        anchors.fill: parent
        visible: !root.isAnimated
        asynchronous: true
        fillMode: root.fillMode
        sourceSize.width: root.maxCacheSize
        sourceSize.height: root.maxCacheSize
        smooth: true

        // save the downscaled render as the cache copy. Retried on visibility
        // (not just Ready): list views keep cacheBuffer delegates invisible, and
        // grabbing an invisible item fails — those save on first scroll-in.
        function maybeSaveCache() {
            if (status !== Image.Ready || root._usingCache || root._cacheSaved || root.isRemoteUrl || !root.cachePath)
                return;
            if (!visible || width <= 0 || height <= 0 || !Window.window?.visible)
                return;
            Paths.mkdir(Paths.imagecache);
            const grabPath = root.cachePath;
            root._cacheSaved = grabToImage(res => res.saveToFile(grabPath));
        }
        onStatusChanged: {
            // cached thumbnail missing → fall back to the original
            if (status === Image.Error && root._usingCache) {
                root._usingCache = false;
                source = root.encodedImagePath;
                return;
            }
            maybeSaveCache();
        }
        onVisibleChanged: maybeSaveCache()
    }

    onImagePathChanged: {
        _cacheSaved = false;
        if (!imagePath) {
            _usingCache = false;
            staticImg.source = "";
            return;
        }
        if (isAnimated)
            return;
        if (isRemoteUrl) {
            _usingCache = false;
            staticImg.source = imagePath;
            return;
        }
        // load the cached thumbnail directly — a miss falls back to the
        // original in onStatusChanged (Image.Error). No per-image process
        // probe: spawning `test -f` per thumbnail serialized every load
        // behind a process round-trip.
        // cachePath is already a file:// URL string (Paths.stringify keeps the scheme)
        _usingCache = !!cachePath;
        staticImg.source = cachePath || encodedImagePath;
    }
}
