import LeanWebStudy.Page

private def client : String := r##"
<script>
(() => {
  const canvas = document.getElementById("court");
  const context = canvas.getContext("2d");
  const status = document.getElementById("status");
  const error = document.getElementById("error");
  const up = document.getElementById("up");
  const down = document.getElementById("down");
  const url = new URL("/pong/socket", location.href);
  url.protocol = location.protocol === "https:" ? "wss:" : "ws:";
  const port = document.querySelector('meta[name="leanwebstudy-chat-port"]').content;
  if (port) url.port = port;

  const court = {width: 800, height: 450, paddleHeight: 80};
  const paddles = [185, 185];
  const ball = {x: 400, y: 225};
  let targetBall = {x: 400, y: 225};
  let player = 0;
  let players = 0;
  let score = [0, 0];
  let socket;
  let direction = 0;
  let retry;
  let retryDelay = 1000;
  let lastFrame = 0;
  let lastPaddleSent = 0;
  let lastBallSent = 0;
  let velocity = {x: 280, y: 150};
  let stopped = false;
  let gameOver = false;

  function connect() {
    if (stopped || (socket && socket.readyState !== WebSocket.CLOSED)) return;
    status.textContent = "WebSocket に接続中…";
    try {
      socket = new WebSocket(url, "leanwebstudy-pong");
    } catch (failure) {
      error.textContent = "接続できません: " + failure.message;
      return;
    }
    socket.onopen = () => {
      retryDelay = 1000;
      error.textContent = "";
      status.textContent = "接続済み — もう一人の参加者を待っています";
    };
    socket.onmessage = event => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "welcome" && Number.isInteger(data.player) &&
            data.player >= 0 && data.player <= 2) {
          player = data.player;
          status.textContent = player ? `プレイヤー ${player} として参加中` : "観戦中";
        } else if (data.type === "players" && Number.isInteger(data.count) &&
                   data.count >= 0 && data.count <= 2) {
          players = data.count;
          status.textContent = players < 2
            ? "もう一人の参加者を待っています"
            : `プレイヤー ${player} — 対戦中`;
        } else if (data.type === "update" && (data.player === 1 || data.player === 2) &&
                   data.event && typeof data.event === "object") {
          const update = data.event;
          if (update.type === "paddle" && Number.isInteger(update.y) &&
              update.y >= 0 && update.y <= 370) {
            paddles[data.player - 1] = update.y;
          } else if (update.type === "ball" &&
                     Number.isInteger(update.x) && update.x >= 0 && update.x <= 800 &&
                     Number.isInteger(update.y) && update.y >= 0 && update.y <= 450 &&
                     Number.isInteger(update.left) && update.left >= 0 && update.left <= 7 &&
                     Number.isInteger(update.right) && update.right >= 0 && update.right <= 7) {
            targetBall = {x: update.x, y: update.y};
            score = [update.left, update.right];
            gameOver = score[0] >= 7 || score[1] >= 7;
          } else {
            throw new Error("ゲームイベントの形式が不正です。");
          }
        } else if (data.type === "error" && typeof data.message === "string") {
          error.textContent = data.message;
        } else {
          throw new Error("サーバーから不正なイベントを受信しました。");
        }
      } catch (failure) {
        error.textContent = failure.message;
        socket.close(1002, "invalid server event");
      }
    };
    socket.onerror = () => { error.textContent = "WebSocket 通信に失敗しました。"; };
    socket.onclose = () => {
      player = 0;
      players = 0;
      status.textContent = "切断されました。再接続しています…";
      if (!stopped) {
        retry = setTimeout(connect, retryDelay);
        retryDelay = Math.min(retryDelay * 2, 10000);
      }
    };
  }

  function send(data) {
    if (!socket || socket.readyState !== WebSocket.OPEN || socket.bufferedAmount > 8192)
      return;
    socket.send(JSON.stringify(data));
  }

  function setDirection(value) {
    direction = value;
  }
  for (const [button, value] of [[up, -1], [down, 1]]) {
    button.addEventListener("pointerdown", event => {
      event.preventDefault();
      setDirection(value);
      button.setPointerCapture(event.pointerId);
    });
    for (const name of ["pointerup", "pointercancel", "lostpointercapture"])
      button.addEventListener(name, () => setDirection(0));
  }
  window.addEventListener("keydown", event => {
    if (["ArrowUp", "ArrowDown", "w", "W", "s", "S"].includes(event.key))
      event.preventDefault();
    if (event.key === "ArrowUp" || event.key === "w" || event.key === "W")
      setDirection(-1);
    if (event.key === "ArrowDown" || event.key === "s" || event.key === "S")
      setDirection(1);
    if (event.key === " " && gameOver && player === 1) {
      score = [0, 0];
      ball.x = targetBall.x = 400;
      ball.y = targetBall.y = 225;
      velocity = {x: 280, y: 150};
      gameOver = false;
    }
  });
  window.addEventListener("keyup", event => {
    if (["ArrowUp", "ArrowDown", "w", "W", "s", "S"].includes(event.key))
      setDirection(0);
  });
  window.addEventListener("blur", () => setDirection(0));

  function draw() {
    context.fillStyle = "#101a30";
    context.fillRect(0, 0, court.width, court.height);
    context.strokeStyle = "#52617b";
    context.setLineDash([9, 10]);
    context.beginPath();
    context.moveTo(400, 0);
    context.lineTo(400, 450);
    context.stroke();
    context.setLineDash([]);
    context.fillStyle = "#f3f6ff";
    context.font = "bold 44px system-ui";
    context.textAlign = "center";
    context.fillText(score[0], 330, 58);
    context.fillText(score[1], 470, 58);
    context.fillRect(18, paddles[0], 12, court.paddleHeight);
    context.fillRect(770, paddles[1], 12, court.paddleHeight);
    context.beginPath();
    context.arc(ball.x, ball.y, 9, 0, Math.PI * 2);
    context.fill();
    if (players < 2 || gameOver) {
      context.fillStyle = "rgba(16, 26, 48, .82)";
      context.fillRect(150, 175, 500, 94);
      context.fillStyle = "#ffffff";
      context.font = "20px system-ui";
      context.fillText(
        gameOver ? (score[0] >= 7 ? "左プレイヤーの勝利！" : "右プレイヤーの勝利！")
          : "プレイヤー 2 の参加を待っています",
        400, 218
      );
      if (gameOver && player === 1)
        context.fillText("Space キーで次の試合", 400, 250);
    }
  }

  function frame(now) {
    const dt = lastFrame ? Math.min((now - lastFrame) / 1000, 0.05) : 0;
    lastFrame = now;
    if (player === 1 || player === 2)
      paddles[player - 1] = Math.max(0, Math.min(370,
        paddles[player - 1] + direction * 360 * dt));
    if (player === 1 && players === 2 && !gameOver) {
      const previousX = ball.x;
      ball.x += velocity.x * dt;
      ball.y += velocity.y * dt;
      if (ball.y <= 9) {
        ball.y = 9;
        velocity.y = Math.abs(velocity.y);
      } else if (ball.y >= 441) {
        ball.y = 441;
        velocity.y = -Math.abs(velocity.y);
      }
      if (velocity.x < 0 && previousX > 30 && ball.x <= 30 &&
          ball.y >= paddles[0] - 9 && ball.y <= paddles[0] + 89) {
        ball.x = 30;
        velocity.x = Math.min(500, Math.abs(velocity.x) * 1.04);
        velocity.y += (ball.y - paddles[0] - 40) * 1.5;
      }
      if (velocity.x > 0 && previousX < 758 && ball.x >= 758 &&
          ball.y >= paddles[1] - 9 && ball.y <= paddles[1] + 89) {
        ball.x = 758;
        velocity.x = -Math.min(500, Math.abs(velocity.x) * 1.04);
        velocity.y += (ball.y - paddles[1] - 40) * 1.5;
      }
      velocity.y = Math.max(-480, Math.min(480, velocity.y));
      if (ball.x < 0 || ball.x > 800) {
        if (ball.x < 0) score[1]++;
        else score[0]++;
        gameOver = score[0] >= 7 || score[1] >= 7;
        ball.x = 400;
        ball.y = 225;
        velocity = {x: score[0] > score[1] ? 280 : -280, y: 150};
      }
      if (now - lastBallSent >= 50) {
        send({type: "ball", x: Math.round(ball.x), y: Math.round(ball.y),
          left: score[0], right: score[1]});
        lastBallSent = now;
      }
    } else if (player === 2) {
      ball.x += (targetBall.x - ball.x) * 0.35;
      ball.y += (targetBall.y - ball.y) * 0.35;
    }
    if (player && now - lastPaddleSent >= 75) {
      send({type: "paddle", y: Math.round(paddles[player - 1])});
      lastPaddleSent = now;
    }
    draw();
    requestAnimationFrame(frame);
  }

  connect();
  requestAnimationFrame(frame);
  window.addEventListener("pagehide", () => {
    stopped = true;
    clearTimeout(retry);
    if (socket) socket.close(1000, "leaving page");
  });
})();
</script>
"##

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
      s!"<meta name=\"leanwebstudy-chat-port\" content=\"{context.chatPort}\">" ++
      "<title>WebSocket Pong - LeanWebStudy</title>" ++
      "<style>body{font-family:system-ui,sans-serif;background:#f4f6fb;color:#17243b;margin:0}" ++
      "main{max-width:900px;margin:auto;padding:24px}section{background:white;padding:20px;" ++
      "border-radius:12px;margin:16px 0}canvas{display:block;width:100%;height:auto;" ++
      "border-radius:8px;touch-action:none}.controls{display:flex;gap:12px;justify-content:center}" ++
      "button{font:inherit;padding:12px 28px;touch-action:none}#error{color:#a51c30;min-height:1.5em}" ++
      "</style></head><body><main><p><a href=\"/\">LeanWebStudy</a></p>" ++
      "<h1>通信対戦 Pong</h1>" ++
      "<p>別のタブまたは端末でも開いてください。プレイヤー1が左、プレイヤー2が右です。" ++
      "矢印キー / W・S キー、またはボタンで操作します。</p>" ++
      "<p id=\"status\" role=\"status\">JavaScript を有効にしてください。</p>" ++
      "<section><canvas id=\"court\" width=\"800\" height=\"450\" " ++
      "aria-label=\"Pong のゲーム画面\"></canvas>" ++
      "<div class=\"controls\"><button id=\"up\" type=\"button\">上へ</button>" ++
      "<button id=\"down\" type=\"button\">下へ</button></div>" ++
      "<p id=\"error\" role=\"alert\"></p></section>" ++
      "<p>ボールの状態はプレイヤー1が更新し、パドル操作とボール状態を WebSocket で同期します。" ++
      "先に7点取ると勝利です。学習用サンプルのため、ルームは1つ、認証はありません。</p>" ++
      client ++ "</main></body></html>")
