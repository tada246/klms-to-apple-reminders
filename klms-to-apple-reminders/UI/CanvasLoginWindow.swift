import AppKit
import WebKit

/// K-LMS SSO ログインを WKWebView で処理するウィンドウコントローラー。
///
/// ログイン成功を検出すると Cookie を抽出し、CanvasAuthService 経由でアクセストークンを生成。
/// トークンと Cookie を Keychain に保存してから `onSuccess` を呼ぶ。
/// ユーザーがウィンドウを閉じた場合は `onDismiss` を呼ぶ（ログインは未完了）。
class CanvasLoginWindowController: NSWindowController {

    var onSuccess: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var webView: WKWebView!
    private var navDelegate: LoginNavDelegate?
    private var didComplete = false

    // MARK: - Factory

    static func present() -> CanvasLoginWindowController {
        let controller = CanvasLoginWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    // MARK: - Init

    init() {
        // 既存の WKWebView セッション（Shibboleth SSO）を活かすためデフォルトの永続ストアを使用。
        // 再ログイン時に Shibboleth セッションが残っていれば自動でログインが完了する。
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let frame = NSRect(x: 0, y: 0, width: 860, height: 640)
        let wv = WKWebView(frame: frame, configuration: config)
        webView = wv

        let window = NSWindow(
            contentRect: frame,
            styleMask:   [.titled, .closable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "K-LMS ログイン"
        window.contentView = wv
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self

        let delegate = LoginNavDelegate(owner: self)
        navDelegate = delegate
        wv.navigationDelegate = delegate

        wv.load(URLRequest(url: URL(string: "https://lms.keio.jp/login/saml")!))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Internal

    /// ログイン成功後に Cookie リストを受け取り、トークン生成まで処理する。
    @MainActor
    func handleLoginSuccess(cookies: [HTTPCookie]) async {
        guard !didComplete else { return }
        didComplete = true

        let cookieHeader = CanvasAuthService.buildCookieHeader(from: cookies)

        do {
            let token = try await CanvasAuthService.generateToken(cookieHeader: cookieHeader)
            try KeychainHelper.save(token)
            try KeychainHelper.saveCookie(cookieHeader)
            UserDefaults.standard.set(Date(), forKey: "lastLoginDate")

            onSuccess?()
            window?.close()
        } catch {
            // トークン生成に失敗した場合はエラーを表示してリトライ可能にする
            didComplete = false
            let alert = NSAlert()
            alert.messageText = "ログイン処理でエラーが発生しました"
            alert.informativeText = """
                \(error.localizedDescription)

                ページが完全に読み込まれるのを待ってから、もう一度お試しください。
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let win = window {
                await alert.beginSheetModal(for: win)
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension CanvasLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !didComplete else { return }
        onDismiss?()
    }
}

// MARK: - WKNavigationDelegate (private helper class)

private class LoginNavDelegate: NSObject, WKNavigationDelegate {
    weak var owner: CanvasLoginWindowController?

    init(owner: CanvasLoginWindowController) {
        self.owner = owner
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let urlString = url.absoluteString

        // lms.keio.jp 上かつログインページではない → ログイン成功の可能性あり
        guard urlString.hasPrefix("https://lms.keio.jp"),
              !urlString.contains("/login")
        else { return }

        // canvas_session Cookie の存在を確認
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let hasSession = cookies.contains {
                $0.name == "canvas_session" && $0.domain.contains("lms.keio.jp")
            }
            guard hasSession else { return }

            Task { @MainActor [weak self] in
                await self?.owner?.handleLoginSuccess(cookies: cookies)
            }
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        // リダイレクト中のキャンセルは無視
        let nsErr = error as NSError
        guard nsErr.code != NSURLErrorCancelled else { return }
        #if DEBUG
        print("[CanvasLogin] navigation error: \(error.localizedDescription)")
        #endif
    }
}
