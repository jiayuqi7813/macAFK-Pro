import Foundation
import CoreGraphics
import Combine
import os

class Jiggler: ObservableObject {
    @Published var isRunning = false
    @Published var currentInterval: TimeInterval = 60 {
        didSet {
            if !isLoading {
                saveInterval()
            }
        }
    }

    private var timer: Timer?

    private let intervalPresets: [TimeInterval] = [10, 30, 60, 120, 300, 600]
    private var currentPresetIndex: Int = 2 {
        didSet {
            if !isLoading {
                saveInterval()
            }
        }
    }

    private let intervalKey = "jiggler.interval"
    private let presetIndexKey = "jiggler.presetIndex"
    private var isLoading = false

    init() {
        loadInterval()
    }

    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        guard !isRunning else { return }

        isRunning = true

        let newTimer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            self?.jiggleMouse()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer

        jiggleMouse()
        debugLog("Started with interval \(Int(currentInterval))s", logger: AppLog.jiggler)
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }

        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        debugLog("Stopped", logger: AppLog.jiggler)
    }

    func increaseInterval() {
        guard currentPresetIndex < intervalPresets.count - 1 else { return }

        currentPresetIndex += 1
        currentInterval = intervalPresets[currentPresetIndex]

        if isRunning {
            restart()
        }
        debugLog("Interval increased to \(Int(currentInterval))s", logger: AppLog.jiggler)
    }

    func decreaseInterval() {
        guard currentPresetIndex > 0 else { return }

        currentPresetIndex -= 1
        currentInterval = intervalPresets[currentPresetIndex]

        if isRunning {
            restart()
        }
        debugLog("Interval decreased to \(Int(currentInterval))s", logger: AppLog.jiggler)
    }

    func setInterval(_ interval: TimeInterval) {
        currentInterval = interval

        if let closestIndex = intervalPresets.enumerated().min(by: { abs($0.element - interval) < abs($1.element - interval) })?.offset {
            currentPresetIndex = closestIndex
        }

        if isRunning {
            restart()
        }
        debugLog("Interval set to \(Int(currentInterval))s", logger: AppLog.jiggler)
    }

    private func restart() {
        stop()
        start()
    }

    func getIntervalDisplay() -> String {
        if currentInterval < 60 {
            return "\(Int(currentInterval)) s"
        }
        let minutes = Int(currentInterval / 60)
        return "\(minutes) min"
    }

    private func saveInterval() {
        UserDefaults.standard.set(currentInterval, forKey: intervalKey)
        UserDefaults.standard.set(currentPresetIndex, forKey: presetIndexKey)
    }

    private func loadInterval() {
        isLoading = true
        defer { isLoading = false }

        if let savedInterval = UserDefaults.standard.object(forKey: intervalKey) as? TimeInterval,
           savedInterval > 0 {
            currentInterval = savedInterval

            let savedIndex = UserDefaults.standard.integer(forKey: presetIndexKey)
            if savedIndex >= 0 && savedIndex < intervalPresets.count {
                currentPresetIndex = savedIndex
            } else if let closestIndex = intervalPresets.enumerated().min(by: { abs($0.element - savedInterval) < abs($1.element - savedInterval) })?.offset {
                currentPresetIndex = closestIndex
            }
            debugLog("Loaded interval \(Int(currentInterval))s", logger: AppLog.jiggler)
        } else {
            currentInterval = 60
            currentPresetIndex = 2
            debugLog("Using default interval 60s", logger: AppLog.jiggler)
        }
    }

    private func jiggleMouse() {
        guard let currentEvent = CGEvent(source: nil) else {
            AppLog.jiggler.error("Unable to create CGEvent — accessibility permission may be missing")
            return
        }

        let mouseLocation = currentEvent.location
        let newLocation = CGPoint(x: mouseLocation.x + 1, y: mouseLocation.y)
        let moveRight = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newLocation,
            mouseButton: .left
        )
        moveRight?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard self?.isRunning == true else { return }

            let moveBack = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: mouseLocation,
                mouseButton: .left
            )
            moveBack?.post(tap: .cghidEventTap)
        }
    }
}
