declare global {
  interface Window {
    __MEMOS_BOOTSTRAP_ERROR__?: string;
  }
}

export {};

const title = document.querySelector<HTMLHeadingElement>("#title");
const message = document.querySelector<HTMLParagraphElement>("#message");

function setScreenState(): void {
  if (!title || !message) {
    return;
  }

  const bootstrapError = window.__MEMOS_BOOTSTRAP_ERROR__;
  if (bootstrapError) {
    title.textContent = "Configuration error";
    message.textContent = bootstrapError;
    return;
  }

  title.textContent = "Ready for remote bootstrap";
  message.textContent =
    "The local assets are packaged correctly. In Android builds, Rust should create the remote Memos window instead of leaving this page on screen.";
}

window.addEventListener("DOMContentLoaded", setScreenState);
