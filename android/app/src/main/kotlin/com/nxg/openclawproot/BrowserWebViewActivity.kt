package com.nxg.openclawproot

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import org.json.JSONTokener

class BrowserWebViewActivity : Activity() {
    private lateinit var webView: WebView
    private lateinit var urlInput: EditText
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setContentView(buildLayout())

        val url = intent.getStringExtra("url") ?: "https://www.baidu.com"
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = true
            displayZoomControls = false
            javaScriptCanOpenWindowsAutomatically = true
            @Suppress("DEPRECATION")
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
        webView.webViewClient = object : WebViewClient() {}
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.progress = newProgress
                progressBar.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }
        }
        activeWebView = webView
        webView.loadUrl(normalizeUrl(url))
        refreshStructure()
    }

    override fun onDestroy() {
        activeWebView = null
        webView.destroy()
        super.onDestroy()
    }

    private fun buildLayout(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }

        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(6.dp(), 4.dp(), 6.dp(), 4.dp())
            setBackgroundColor(Color.rgb(240, 240, 240))
        }

        val backBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_revert)
            background = null
            setOnClickListener { if (webView.canGoBack()) webView.goBack() }
        }
        topBar.addView(backBtn, LinearLayout.LayoutParams(44.dp(), 44.dp()))

        urlInput = EditText(this).apply {
            hint = "输入网址"
            textSize = 14f
            setSingleLine(true)
            background = null
        }
        topBar.addView(urlInput, LinearLayout.LayoutParams(0, 44.dp(), 1f))

        val goBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_media_play)
            background = null
            setOnClickListener { go() }
        }
        topBar.addView(goBtn, LinearLayout.LayoutParams(44.dp(), 44.dp()))

        val closeBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            background = null
            setOnClickListener { finish() }
        }
        topBar.addView(closeBtn, LinearLayout.LayoutParams(44.dp(), 44.dp()))

        root.addView(
            topBar,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = 0
            visibility = View.GONE
        }
        root.addView(
            progressBar,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 6.dp())
        )

        webView = WebView(this)
        val frame = FrameLayout(this)
        frame.addView(
            webView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        )
        root.addView(
            frame,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
        )

        return root
    }

    private fun go() {
        val text = urlInput.text.toString().trim()
        if (text.isNotEmpty()) {
            webView.loadUrl(normalizeUrl(text))
        }
    }

    private fun Int.dp(): Int = (this * resources.displayMetrics.density).toInt()

    companion object {
        @Volatile private var activeWebView: WebView? = null
        @Volatile private var latestStructure: String = ""

        fun isActive(): Boolean = activeWebView != null

        fun getStructure(): String = latestStructure

        fun refreshStructure() {
            val wv = activeWebView ?: return
            wv.post {
                wv.evaluateJavascript(structureJs()) { value ->
                    latestStructure = decodeJsString(value ?: "")
                }
            }
        }

        fun clickElement(index: Int) {
            val wv = activeWebView ?: return
            wv.post {
                wv.evaluateJavascript(clickJs(index)) { _ ->
                    Handler(Looper.getMainLooper()).postDelayed({ refreshStructure() }, 900)
                }
            }
        }

        fun inputText(index: Int, text: String) {
            val wv = activeWebView ?: return
            val safe = text.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
            wv.post {
                wv.evaluateJavascript(inputJs(index, safe), null)
            }
        }

        fun scrollPage(direction: String) {
            val wv = activeWebView ?: return
            val delta = if (direction == "up") "-Math.round(window.innerHeight * 0.7)" else "Math.round(window.innerHeight * 0.7)"
            wv.post {
                wv.evaluateJavascript("window.scrollBy(0, $delta); true;", null)
            }
        }

        fun normalizeUrl(url: String): String {
            val u = url.trim()
            if (u.startsWith("http://") || u.startsWith("https://")) return u
            return "https://$u"
        }

        private fun decodeJsString(value: String): String {
            return try {
                if (value.length >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
                    JSONTokener(value).nextValue().toString()
                } else value
            } catch (_: Exception) {
                value
            }
        }

        private fun structureJs(): String {
            return """
                (function() {
                    var els = document.querySelectorAll('a, button, input, textarea, select, [role="button"], [role="link"], [onclick]');
                    var out = [];
                    var count = 0;
                    for (var i = 0; i < els.length && out.length < 80; i++) {
                        var el = els[i];
                        var tag = (el.tagName || '').toLowerCase();
                        var isHidden = tag === 'input' && (el.getAttribute('type') || 'text').toLowerCase() === 'hidden';
                        if (isHidden) continue;
                        if (tag === 'input' && ((el.getAttribute('type') || 'text').toLowerCase() === 'submit' || (el.getAttribute('type') || 'text').toLowerCase() === 'button')) tag = 'button';
                        if (!(tag === 'a' || tag === 'button' || tag === 'input' || tag === 'textarea' || tag === 'select' || el.getAttribute('role') || el.getAttribute('onclick'))) continue;
                        var text = '';
                        if (tag === 'input') {
                            text = el.value || el.getAttribute('placeholder') || el.getAttribute('name') || '';
                        } else if (tag === 'textarea') {
                            text = el.getAttribute('placeholder') || '';
                        } else {
                            text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim().replace(/\s+/g, ' ').substring(0, 80);
                        }
                        var href = el.href || '';
                        out.push({idx: count, type: tag, text: text, href: href.substring(0, 120)});
                        count++;
                    }
                    return JSON.stringify(out);
                })();
            """.trimIndent()
        }

        private fun clickJs(index: Int): String {
            return """
                (function() {
                    var els = document.querySelectorAll('a, button, input, textarea, select, [role="button"], [role="link"], [onclick]');
                    var count = 0;
                    for (var i = 0; i < els.length; i++) {
                        var el = els[i];
                        var tag = (el.tagName || '').toLowerCase();
                        var isHidden = tag === 'input' && (el.getAttribute('type') || 'text').toLowerCase() === 'hidden';
                        if (isHidden) continue;
                        if (tag === 'input' && ((el.getAttribute('type') || 'text').toLowerCase() === 'submit' || (el.getAttribute('type') || 'text').toLowerCase() === 'button')) tag = 'button';
                        if (!(tag === 'a' || tag === 'button' || tag === 'input' || tag === 'textarea' || tag === 'select' || el.getAttribute('role') || el.getAttribute('onclick'))) continue;
                        if (count === $index) {
                            el.click();
                            return true;
                        }
                        count++;
                    }
                    return false;
                })();
            """.trimIndent()
        }

        private fun inputJs(index: Int, text: String): String {
            return """
                (function() {
                    var els = document.querySelectorAll('input, textarea, select');
                    var count = 0;
                    for (var i = 0; i < els.length; i++) {
                        var el = els[i];
                        if (el.tagName === 'INPUT' && (el.getAttribute('type') || 'text').toLowerCase() === 'hidden') continue;
                        if (count === $index) {
                            if (el.tagName === 'SELECT') {
                                for (var o = 0; o < el.options.length; o++) {
                                    if (el.options[o].value === '$text' || el.options[o].text === '$text') { el.selectedIndex = o; break; }
                                }
                            } else {
                                el.value = '$text';
                                el.dispatchEvent(new Event('input', {bubbles: true}));
                                el.dispatchEvent(new Event('change', {bubbles: true}));
                            }
                            return true;
                        }
                        count++;
                    }
                    return false;
                })();
            """.trimIndent()
        }
    }
}
