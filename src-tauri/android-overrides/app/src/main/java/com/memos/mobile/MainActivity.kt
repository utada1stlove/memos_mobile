package com.memos.mobile

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.SslErrorHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import org.json.JSONObject

class MainActivity : TauriActivity() {
  private lateinit var webView: WebView
  private var allowedOrigin: Uri? = null
  private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
  private var pendingSharePayload: String? = null
  private var shareAttempts = 0
  private var errorOverlay: View? = null
  private var errorMessageView: TextView? = null

  private val filePickerLauncher =
    registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
      val callback = fileChooserCallback
      fileChooserCallback = null

      if (callback == null) {
        return@registerForActivityResult
      }

      val uris = WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
      callback.onReceiveValue(uris ?: emptyArray())
    }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleIncomingIntent(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIncomingIntent(intent)
  }

  @SuppressLint("SetJavaScriptEnabled")
  override fun onWebViewCreate(webView: WebView) {
    this.webView = webView

    WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)

    with(webView.settings) {
      javaScriptEnabled = true
      domStorageEnabled = true
      databaseEnabled = true
      allowContentAccess = true
      allowFileAccess = false
      mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
    }

    installErrorOverlay()

    webView.webChromeClient =
      object : WebChromeClient() {
        override fun onShowFileChooser(
          view: WebView?,
          filePathCallback: ValueCallback<Array<Uri>>?,
          fileChooserParams: FileChooserParams?
        ): Boolean {
          if (filePathCallback == null) {
            return false
          }

          fileChooserCallback?.onReceiveValue(null)
          fileChooserCallback = filePathCallback

          return try {
            val chooserIntent = fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT)
            filePickerLauncher.launch(chooserIntent)
            true
          } catch (_: ActivityNotFoundException) {
            fileChooserCallback = null
            Toast.makeText(
              this@MainActivity,
              "No compatible file picker is available on this device.",
              Toast.LENGTH_LONG
            ).show()
            false
          }
        }
      }

    webView.webViewClient =
      object : WebViewClient() {
        override fun shouldOverrideUrlLoading(
          view: WebView?,
          request: WebResourceRequest?
        ): Boolean {
          if (request == null || !request.isForMainFrame) {
            return false
          }

          val target = request.url ?: return false
          return if (isAllowedNavigation(target)) {
            false
          } else {
            openExternalUrl(target)
            true
          }
        }

        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
          super.onPageStarted(view, url, favicon)
          hideErrorOverlay()
          if (allowedOrigin == null && url != null) {
            allowedOrigin = Uri.parse(url)
          }
        }

        override fun onPageFinished(view: WebView?, url: String?) {
          super.onPageFinished(view, url)
          hideErrorOverlay()
          if (allowedOrigin == null && url != null) {
            allowedOrigin = Uri.parse(url)
          }
          maybeDeliverPendingShare()
        }

        override fun onReceivedError(
          view: WebView?,
          request: WebResourceRequest?,
          error: WebResourceError?
        ) {
          super.onReceivedError(view, request, error)
          if (request?.isForMainFrame == true) {
            showErrorOverlay(describeWebError(error))
          }
        }

        override fun onReceivedSslError(
          view: WebView?,
          handler: SslErrorHandler?,
          error: SslError?
        ) {
          handler?.cancel()
          showErrorOverlay("Secure connection failed. Check the server certificate and try again.")
        }
      }

    maybeDeliverPendingShare()
  }

  override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
    if (keyCode == KeyEvent.KEYCODE_BACK && ::webView.isInitialized && webView.canGoBack()) {
      webView.goBack()
      return true
    }

    return super.onKeyDown(keyCode, event)
  }

  private fun handleIncomingIntent(intent: Intent?) {
    if (intent == null || intent.action != Intent.ACTION_SEND) {
      return
    }

    if (intent.type?.startsWith("text/") != true) {
      return
    }

    val payload = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
    if (payload.isBlank()) {
      return
    }

    pendingSharePayload = payload
    shareAttempts = 0

    Toast.makeText(
      this,
      "Opening Memos share flow...",
      Toast.LENGTH_SHORT
    ).show()

    maybeDeliverPendingShare()
  }

  private fun maybeDeliverPendingShare() {
    val payload = pendingSharePayload ?: return
    if (!::webView.isInitialized || allowedOrigin == null) {
      return
    }

    shareAttempts += 1
    val quotedPayload = JSONObject.quote(payload)

    webView.evaluateJavascript(
      """
        (function () {
          try {
            const api = window.__MEMOS_MOBILE__;
            if (api && typeof api.tryInsertSharedPayload === "function") {
              return api.tryInsertSharedPayload($quotedPayload);
            }
          } catch (_) {
          }
          return false;
        })();
      """.trimIndent()
    ) { result ->
      if (result == "true") {
        pendingSharePayload = null
        shareAttempts = 0
        Toast.makeText(this, "Shared text inserted into the page.", Toast.LENGTH_SHORT).show()
        return@evaluateJavascript
      }

      if (shareAttempts >= 2) {
        copyToClipboard(payload)
        pendingSharePayload = null
        shareAttempts = 0
        Toast.makeText(
          this,
          "Could not auto-fill the composer. The shared text was copied to clipboard.",
          Toast.LENGTH_LONG
        ).show()
      }
    }
  }

  private fun isAllowedNavigation(target: Uri): Boolean {
    val origin = allowedOrigin ?: return true
    val scheme = target.scheme?.lowercase() ?: return false

    if (scheme == "about") {
      return true
    }

    if (scheme != "http" && scheme != "https") {
      return false
    }

    val originScheme = origin.scheme?.lowercase() ?: return false
    val targetHost = target.host ?: return false
    val originHost = origin.host ?: return false

    return scheme == originScheme &&
      targetHost.equals(originHost, ignoreCase = true) &&
      effectivePort(target) == effectivePort(origin)
  }

  private fun effectivePort(uri: Uri): Int {
    return when {
      uri.port != -1 -> uri.port
      uri.scheme.equals("https", ignoreCase = true) -> 443
      uri.scheme.equals("http", ignoreCase = true) -> 80
      else -> -1
    }
  }

  private fun openExternalUrl(uri: Uri) {
    val intent =
      Intent(Intent.ACTION_VIEW, uri).apply {
        addCategory(Intent.CATEGORY_BROWSABLE)
      }

    try {
      startActivity(intent)
    } catch (_: ActivityNotFoundException) {
      Toast.makeText(this, "No browser is available to open this link.", Toast.LENGTH_LONG).show()
    }
  }

  private fun copyToClipboard(payload: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Memos share payload", payload))
  }

  private fun describeWebError(error: WebResourceError?): String {
    return when (error?.errorCode) {
      WebViewClient.ERROR_HOST_LOOKUP ->
        "Cannot reach the Memos server. Check the host name and your network connection."
      WebViewClient.ERROR_TIMEOUT ->
        "The request timed out. Check the server and try again."
      WebViewClient.ERROR_CONNECT ->
        "The app could not connect to the Memos server."
      WebViewClient.ERROR_IO ->
        "A network error interrupted the request."
      WebViewClient.ERROR_UNSUPPORTED_AUTH_SCHEME ->
        "The server requested an authentication scheme that this wrapper does not support."
      else ->
        "The page could not be loaded. Check your connection and server configuration, then retry."
    }
  }

  private fun installErrorOverlay() {
    if (errorOverlay != null) {
      return
    }

    val titleView =
      TextView(this).apply {
        text = "Connection problem"
        textSize = 22f
        setTextColor(0xFFF4F1E8.toInt())
      }

    val messageView =
      TextView(this).apply {
        text = "The page could not be loaded."
        textSize = 15f
        setTextColor(0xFFD5DDD9.toInt())
      }

    val retryButton =
      Button(this).apply {
        text = "Retry"
        setOnClickListener {
          hideErrorOverlay()
          if (::webView.isInitialized) {
            webView.reload()
          }
        }
      }

    val overlay =
      LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(48, 48, 48, 48)
        setBackgroundColor(0xEE08120F.toInt())
        visibility = View.GONE
        addView(titleView)
        addView(messageView)
        addView(retryButton)
      }

    addContentView(
      overlay,
      ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
      )
    )

    errorOverlay = overlay
    errorMessageView = messageView
  }

  private fun showErrorOverlay(message: String) {
    errorMessageView?.text = message
    errorOverlay?.visibility = View.VISIBLE
  }

  private fun hideErrorOverlay() {
    errorOverlay?.visibility = View.GONE
  }
}
