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
  const reconnect = document.getElementById("reconnect");
  const messages = document.getElementById("messages");
  let socket;
  let ready = false;
  let retry;
  let delay = 1000;
  let stopped = false;
  let lastId = 0;
  let pending = false;
  let uncertain = false;
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
  function connect() {
    clearTimeout(retry);
    if (socket && socket.readyState !== WebSocket.CLOSED) return;
    ready = false;
    send.disabled = true;
    status.textContent = "接続中…";
    const url = new URL("/chat/socket", location.href);
    url.protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const port = document.querySelector('meta[name="leanwebstudy-chat-port"]').content;
    if (port) url.port = port;
    try {
      socket = new WebSocket(url, "leanwebstudy-chat");
    } catch (failure) {
      status.textContent = "接続できません。";
      error.textContent = failure.message;
      return;
    }
    socket.onmessage = event => {
      try {
        const entry = JSON.parse(event.data);
        if (entry.type === "history") {
          if (!Array.isArray(entry.messages)) throw new Error("履歴の形式が不正です。");
          messages.replaceChildren();
          lastId = 0;
          entry.messages.forEach(show);
          ready = true;
          delay = 1000;
          send.disabled = false;
          status.textContent = "接続済み — WebSocket でリアルタイム配信中";
          if (!uncertain) error.textContent = "";
        } else if (entry.type === "message") {
          show(entry);
          if (pending && entry.requestId === pending.id) {
            if (message.value === pending.draft) message.value = "";
            pending = false;
            uncertain = false;
            error.textContent = "";
            send.disabled = !ready;
            message.focus();
          }
        } else if (entry.type === "error") {
          pending = false;
          send.disabled = !ready;
          error.textContent = entry.message;
        } else {
          throw new Error("不明なイベントを受信しました。");
        }
      } catch (failure) {
        error.textContent = failure.message;
        socket.close(1002, "invalid server event");
      }
    };
    socket.onerror = () => { error.textContent = "WebSocket 通信に失敗しました。"; };
    socket.onclose = () => {
      ready = false;
      send.disabled = true;
      if (pending) {
        uncertain = true;
        error.textContent = "送信結果を確認できません。履歴を確認してから再送してください。";
      }
      pending = false;
      status.textContent = "切断されました。自動再接続を待つか「再接続」を押してください。";
      if (!stopped) {
        retry = setTimeout(connect, delay);
        delay = Math.min(delay * 2, 10000);
      }
    };
  }
  form.addEventListener("submit", event => {
    event.preventDefault();
    if (!ready || pending || socket.readyState !== WebSocket.OPEN) {
      error.textContent = "接続が完了してから送信してください。";
      return;
    }
    const name = author.value.trim();
    const body = message.value.trim();
    if (!name || [...name].length > 24 || !body || [...body].length > 500) {
      error.textContent = "名前は 1〜24 文字、メッセージは 1〜500 文字で入力してください。";
      return;
    }
    if (socket.bufferedAmount > 8192) {
      error.textContent = "送信が混み合っています。少し待ってください。";
      return;
    }
    try {
      const id = crypto.randomUUID();
      socket.send(JSON.stringify({type: "message", author: name, message: body, requestId: id}));
      pending = {id, draft: message.value};
      send.disabled = true;
      error.textContent = "サーバーからの配信を待っています…";
    } catch (failure) {
      error.textContent = "送信できませんでした: " + failure.message;
    }
  });
  reconnect.addEventListener("click", connect);
  window.addEventListener("pagehide", () => {
    stopped = true;
    clearTimeout(retry);
    if (socket) socket.close(1000, "leaving page");
  });
  window.addEventListener("pageshow", event => {
    if (event.persisted) { stopped = false; connect(); }
  });
  connect();
})();
</script>
"#

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
      s!"<meta name=\"leanwebstudy-chat-port\" content=\"{context.chatPort}\">" ++
      "<title>リアルタイムチャット - LeanWebStudy</title>" ++
      "<style>body{font-family:system-ui,sans-serif;background:#f4f6fb;color:#17243b;margin:0}" ++
      "main{max-width:760px;margin:auto;padding:24px}section{background:white;padding:20px;" ++
      "border-radius:12px;margin:16px 0}label{display:block;margin:12px 0 6px}" ++
      "input,textarea{box-sizing:border-box;width:100%;padding:10px;font:inherit}" ++
      "button{padding:10px 16px;margin:12px 6px 0 0;cursor:pointer}" ++
      "#messages{height:300px;overflow:auto;padding-left:24px}li{padding:8px}" ++
      "li p{white-space:pre-wrap;overflow-wrap:anywhere;margin:4px 0}" ++
      "#error{color:#a51c30;min-height:1.5em}</style></head><body><main>" ++
      "<p><a href=\"/\">LeanWebStudy</a></p><h1>リアルタイムチャット</h1>" ++
      "<p>別のタブでも開いてみてください。送信すると全員にすぐ配信されます。</p>" ++
      "<p id=\"status\" role=\"status\">JavaScript を有効にしてください。</p>" ++
      "<button id=\"reconnect\" type=\"button\">再接続</button>" ++
      "<section><h2>メッセージ（最新50件）</h2>" ++
      "<ol id=\"messages\" aria-live=\"polite\" aria-relevant=\"additions\" role=\"log\"></ol></section>" ++
      "<section><h2>送信</h2><form id=\"chat-form\">" ++
      "<label for=\"author\">名前（24文字以内）</label>" ++
      "<input id=\"author\" required autocomplete=\"nickname\">" ++
      "<label for=\"message\">メッセージ（500文字以内）</label>" ++
      "<textarea id=\"message\" rows=\"3\" required></textarea>" ++
      "<button id=\"send\" type=\"submit\" disabled>送信する</button>" ++
      "</form><p id=\"error\" role=\"alert\"></p></section>" ++
      "<p>認証のないローカル学習用サンプルです。最新50件だけをメモリーに保持し、" ++
      "再起動で消えます。切断中の送信や自動再送は行いません。</p></main>" ++ client ++
      "</body></html>")
