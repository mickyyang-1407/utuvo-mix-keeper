import ServiceManagement

enum LoginItem {
    private static let setUpKey = "loginItemSetUp"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("login item error: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: setUpKey)
        log("login item on=\(on) status=\(SMAppService.mainApp.status.rawValue)")
    }

    /// 第一次開啟時預設打開；之後尊重使用者在設定裡的選擇。
    static func setUpOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: setUpKey), Bundle.main.bundleURL.pathExtension == "app" else { return }
        set(true)
    }
}
