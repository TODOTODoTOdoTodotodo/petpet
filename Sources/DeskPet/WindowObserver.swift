import AppKit
import CoreGraphics

public protocol WindowObserverDelegate: AnyObject {
    func windowObserver(_ observer: WindowObserver, didUpdateWindowsByScreen windowsByScreen: [CGDirectDisplayID: [CGRect]])
}

public class WindowObserver {
    public weak var delegate: WindowObserverDelegate?
    private var timer: Timer?
    private let ownPID = getpid()
    
    public init() {}
    
    public func start(interval: TimeInterval = 0.3) {
        stop()
        updateWindows()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateWindows()
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    public func updateWindows() {
        var windowsByScreen: [CGDirectDisplayID: [CGRect]] = [:]
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // Initialize empty lists & baseline dock platforms for each screen
        for screen in screens {
            guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            var platforms: [CGRect] = []
            let vis = screen.visibleFrame
            let frm = screen.frame
            
            // If dock is on this screen at bottom
            if vis.minY > frm.minY {
                let dockLocalRect = CGRect(
                    x: 0,
                    y: 0,
                    width: frm.width,
                    height: vis.minY - frm.minY
                )
                platforms.append(dockLocalRect)
            }
            windowsByScreen[screenID] = platforms
        }
        
        // Main screen height for Quartz -> Cocoa global coordinate conversion
        let mainScreen = screens.first(where: { $0.frame.origin == .zero }) ?? screens[0]
        let mainH = mainScreen.frame.height
        
        if let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowListInfo {
                guard let layer = win[kCGWindowLayer as String] as? Int, layer >= 0 && layer <= 5 else { continue }
                guard let pid = win[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
                
                if let owner = win[kCGWindowOwnerName as String] as? String {
                    if owner == "Window Server" || owner == "Dock" || owner == "DeskPet" {
                        continue
                    }
                }
                
                if let alpha = win[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
                
                guard let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                      let qX = boundsDict["X"] as? Double,
                      let qY = boundsDict["Y"] as? Double,
                      let width = boundsDict["Width"] as? Double,
                      let height = boundsDict["Height"] as? Double else {
                    continue
                }
                
                guard width >= 100, height >= 100 else { continue }                
                // Convert Quartz coordinate to Cocoa Global coordinate
                let globalCocoaY = mainH - (qY + height)
                let globalRect = CGRect(x: qX, y: globalCocoaY, width: width, height: height)
                
                // Route this window to the appropriate screen(s) in local coordinates
                for screen in screens {
                    let frm = screen.frame
                    if frm.intersects(globalRect) {
                        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
                        let localX = globalRect.minX - frm.minX
                        let localY = globalRect.minY - frm.minY
                        let localRect = CGRect(x: localX, y: localY, width: width, height: height)
                        windowsByScreen[screenID]?.append(localRect)
                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.windowObserver(self, didUpdateWindowsByScreen: windowsByScreen)
        }
    }
}
