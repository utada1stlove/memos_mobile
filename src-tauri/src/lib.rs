mod config;

use config::AppConfig;
use tauri::{utils::config::WebviewUrl, Runtime, WebviewWindowBuilder};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            match AppConfig::load() {
                Ok(config) => create_remote_window(app, &config)?,
                Err(error) => create_local_error_window(app, &error.to_string())?,
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Memos Mobile");
}

fn create_remote_window<R: Runtime>(app: &tauri::App<R>, config: &AppConfig) -> tauri::Result<()> {
    let remote_init_script = build_remote_init_script(config);
    let guard_config = config.clone();

    let _window =
        WebviewWindowBuilder::new(app, "main", WebviewUrl::External(config.base_url.clone()))
            .initialization_script(remote_init_script)
            .on_navigation(move |url| guard_config.allows_in_app(url))
            .build()?;

    Ok(())
}

fn create_local_error_window<R: Runtime>(
    app: &tauri::App<R>,
    error_message: &str,
) -> tauri::Result<()> {
    let bootstrap_script = format!(
        "window.__MEMOS_BOOTSTRAP_ERROR__ = {};",
        serde_json::to_string(error_message).expect("error message should serialize")
    );

    let _window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
        .initialization_script(bootstrap_script)
        .build()?;

    Ok(())
}

fn build_remote_init_script(config: &AppConfig) -> String {
    let base_url = serde_json::to_string(config.base_url.as_str()).expect("base URL should serialize");
    let allowed_origin =
        serde_json::to_string(&config.allowed_origin.as_string()).expect("origin should serialize");
    let allow_insecure_http =
        serde_json::to_string(&config.allow_insecure_http).expect("bool should serialize");

    format!(
        r#"
(function () {{
  const shared = window.__MEMOS_MOBILE__ || {{}};
  shared.baseUrl = {base_url};
  shared.allowedOrigin = {allowed_origin};
  shared.allowInsecureHttp = {allow_insecure_http};

  function isVisible(node) {{
    if (!node) {{
      return false;
    }}

    const rect = node.getBoundingClientRect();
    const style = window.getComputedStyle(node);
    return rect.width > 0 && rect.height > 0 && style.display !== "none" && style.visibility !== "hidden";
  }}

  function appendText(current, payload) {{
    if (!current) {{
      return payload;
    }}

    return current.endsWith("\n") ? current + payload : current + "\n" + payload;
  }}

  function dispatchInput(target) {{
    target.dispatchEvent(new Event("input", {{ bubbles: true }}));
    target.dispatchEvent(new Event("change", {{ bubbles: true }}));
  }}

  function insertIntoElement(target, payload) {{
    if (!target || !isVisible(target)) {{
      return false;
    }}

    target.focus();

    if ("value" in target) {{
      target.value = appendText(target.value || "", payload);
      dispatchInput(target);
      return true;
    }}

    if (target.isContentEditable) {{
      target.textContent = appendText(target.textContent || "", payload);
      dispatchInput(target);
      return true;
    }}

    return false;
  }}

  shared.tryInsertSharedPayload = function (payload) {{
    const text = String(payload || "").trim();
    if (!text) {{
      return false;
    }}

    const selectors = [
      "textarea",
      "[contenteditable='true']",
      "[role='textbox']",
      "input[type='text']"
    ];

    for (const selector of selectors) {{
      const nodes = Array.from(document.querySelectorAll(selector));
      for (const node of nodes) {{
        if (insertIntoElement(node, text)) {{
          return true;
        }}
      }}
    }}

    return false;
  }};

  shared.retryCurrentPage = function () {{
    window.location.reload();
    return true;
  }};

  window.__MEMOS_MOBILE__ = shared;
}})();
"#
    )
}
