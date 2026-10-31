import LeanWebStudy.Page

private def client : String := r#"
<script>
(() => {
  const status = document.getElementById("status");
  const error = document.getElementById("error");
  const form = document.getElementById("chat-form");
  const author = document.getElementById("author");
  const message = document.getElementById("message");
  const send = document.getElementById("send");
  const messages = document.getElementById("messages");
  let source;
  let ready = false;
  let lastId = 0;
  let pending = null;
  function acknowledge(entry) {
    if (!pending || entry.requestId !== pending.id) return;
    if (message.value === pending.draft) message.value = "";
    pending = null;
    error.textContent = "";
    send.disabled = !ready;
    message.focus();
  }
  function show(entry) {
    if (!Number.isSafeInteger(entry.id) || entry.id < 1 ||
        typeof entry.author !== "string" || typeof entry.message !== "string")
      throw new Error("不正なメッセージを受信しました。");
    if (entry.id <= lastId) return;
    lastId = entry.id;
    const item = document.createElement("li");
    const name = document.createElement("strong");
    name.textContent = entry.author + " #" + entry.id;
    const text = document.createElement("p");
    text.textContent = entry.message;
    item.append(name, text);
    messages.append(item);
    while (messages.children.length > 50) messages.firstElementChild.remove();
    messages.scrollTop = messages.scrollHeight;
  }
  function receive(event) {
    try {
      const entry = JSON.parse(event.data);
      if (entry.type === "history") {
        if (!Array.isArray(entry.messages)) throw new Error("履歴の形式が不正です。");
        entry.messages.forEach(item => {
          show(item);
          acknowledge(item);
        });
        if (pending) {
          pending = null;
          error.textContent = "再接続後も送信結果を確認できません。履歴を確認してから再送してください。";
        }
        ready = true;
        send.disabled = false;
        status.textContent = "接続済み — SSE でリアルタイム配信中";
      } else if (entry.type === "message") {
        show(entry);
        acknowledge(entry);
      } else {
        throw new Error("不明なイベントを受信しました。");
      }
    } catch (failure) {
      error.textContent = failure.message;
      source.close();
      ready = false;
      send.disabled = true;
    }
  }
  source = new EventSource("/chat-sse/events");
  source.onopen = () => { status.textContent = "接続中 — 履歴を取得しています…"; };
  source.onmessage = receive;
  source.onerror = () => {
    ready = false;
    send.disabled = true;
    status.textContent = "切断されました。EventSource が自動再接続します。";
  };
  form.addEventListener("submit", async event => {
    event.preventDefault();
    if (!ready || pending || source.readyState !== EventSource.OPEN) {
      error.textContent = "接続が完了してから送信してください。";
      return;
    }
    const name = author.value.trim();
    const body = message.value.trim();
    if (!name || [...name].length > 24 || !body || [...body].length > 500) {
      error.textContent = "名前は 1〜24 文字、メッセージは 1〜500 文字で入力してください。";
      return;
    }
    const id = crypto.randomUUID();
    pending = { id, draft: message.value };
    send.disabled = true;
    error.textContent = "サーバーからの配信を待っています…";
    try {
      const response = await fetch("/chat-sse/send", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
        body: new URLSearchParams({ author: name, message: body, requestId: id })
      });
      if (!response.ok) {
        const detail = await response.text();
        throw new Error(detail || "送信に失敗しました。");
      }
    } catch (failure) {
      pending = null;
      send.disabled = !ready;
      error.textContent = "送信結果が不明です。履歴を確認してください: " + failure.message;
    }
  });
  window.addEventListener("pagehide", () => source.close());
})();
</script>
"#

def main : IO Unit :=
  LeanWebStudy.Page.run fun _ =>
    pure ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
      "<title>SSEチャット - LeanWebStudy</title>" ++
      "<style>body{font-family:system-ui,sans-serif;background:#f4f6fb;color:#17243b;margin:0}" ++
      "main{max-width:760px;margin:auto;padding:24px}section{background:white;padding:20px;" ++
      "border-radius:12px;margin:16px 0}label{display:block;margin:12px 0 6px}" ++
      "input,textarea{box-sizing:border-box;width:100%;padding:10px;font:inherit}" ++
      "button{padding:10px 16px;margin:12px 6px 0 0;cursor:pointer}" ++
      "#messages{height:300px;overflow:auto;padding-left:24px}li{padding:8px}" ++
      "li p{white-space:pre-wrap;overflow-wrap:anywhere;margin:4px 0}" ++
      "#error{color:#a51c30;min-height:1.5em}</style></head><body><main>" ++
      "<p><a href=\"/\">LeanWebStudy</a> · <a href=\"/chat/\">WebSocket版</a></p>" ++
      "<h1>SSEリアルタイムチャット</h1>" ++
      "<p>受信はServer-Sent Events、投稿はHTTP POSTで行います。別のタブでも試せます。</p>" ++
      "<p id=\"status\" role=\"status\">JavaScript を有効にしてください。</p>" ++
      "<section><h2>メッセージ（最新50件）</h2>" ++
      "<ol id=\"messages\" aria-live=\"polite\" aria-relevant=\"additions\" role=\"log\"></ol></section>" ++
      "<section><h2>送信</h2><form id=\"chat-form\">" ++
      "<label for=\"author\">名前（24文字以内）</label>" ++
      "<input id=\"author\" required autocomplete=\"nickname\">" ++
      "<label for=\"message\">メッセージ（500文字以内）</label>" ++
      "<textarea id=\"message\" rows=\"3\" required></textarea>" ++
      "<button id=\"send\" type=\"submit\" disabled>送信する</button>" ++
      "</form><p id=\"error\" role=\"alert\"></p></section>" ++
      "<p>認証のないローカル学習用サンプルです。履歴はメモリー上の最新50件で、" ++
      "再起動すると消えます。送信の自動再送は行いません。</p></main>" ++ client ++
      "</body></html>")
