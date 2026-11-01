import LeanWebStudy.Page

private def client : String := r#"
<script>
(() => {
  const currentQuestion = document.getElementById("current-question");
  const questionCount = document.getElementById("question-count");
  const questionProgress = document.getElementById("question-progress");
  const thetaValue = document.getElementById("theta-value");
  const thetaMarker = document.getElementById("theta-marker");
  const expectedProbability = document.getElementById("expected-probability");
  const expectedProbabilityCopy = document.getElementById("expected-probability-copy");
  const estimateChart = document.getElementById("estimate-chart");
  const itemParameters = document.getElementById("item-parameters");
  const historyList = document.getElementById("history-list");
  const status = document.getElementById("status");
  const error = document.getElementById("error");
  const answerButtons = [...document.querySelectorAll("[data-correct]")];
  const resetButton = document.getElementById("reset-button");
  let state;

  function formatMilli(value, digits = 2) {
    return (value / 1000).toFixed(digits);
  }

  function setBusy(busy) {
    answerButtons.forEach(button => button.disabled = busy || !state?.nextItem);
    resetButton.disabled = busy;
  }

  function renderChart(responses, abilityMilli) {
    estimateChart.replaceChildren();
    const points = [{thetaMilli: 0}, ...responses];
    const width = 620;
    const height = 130;
    const left = 20;
    const right = 12;
    const top = 12;
    const bottom = 22;
    const x = index => left + index / 10 * (width - left - right);
    const y = value => top + (4000 - value) / 8000 * (height - top - bottom);
    const ns = "http://www.w3.org/2000/svg";
    const add = (name, attrs = {}) => {
      const element = document.createElementNS(ns, name);
      for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, value);
      estimateChart.append(element);
      return element;
    };
    for (const value of [-2000, 0, 2000]) {
      const lineY = y(value);
      add("line", {x1: left, x2: width - right, y1: lineY, y2: lineY, class: "grid-line"});
      const label = add("text", {x: 2, y: lineY + 4, class: "axis-label"});
      label.textContent = formatMilli(value, 0);
    }
    const coords = points.map((point, index) =>
      `${x(index)},${y(point.thetaMilli ?? abilityMilli)}`).join(" ");
    add("polyline", {points: coords, class: "theta-line"});
    points.forEach((point, index) => add("circle", {
      cx: x(index), cy: y(point.thetaMilli ?? abilityMilli), r: 3.5, class: "theta-dot"
    }));
    const finalLabel = add("text", {x: width - right, y: height - 3, class: "axis-label", "text-anchor": "end"});
    finalLabel.textContent = "回答数";
  }

  function renderHistory(responses) {
    historyList.replaceChildren();
    responses.forEach((response, index) => {
      const row = document.createElement("li");
      const number = document.createElement("span");
      number.className = "history-number";
      number.textContent = String(index + 1).padStart(2, "0");
      const label = document.createElement("span");
      label.textContent = `項目 ${response.itemId} · ${response.correct ? "正解" : "不正解"}`;
      const estimate = document.createElement("strong");
      estimate.textContent = `θ ${formatMilli(response.thetaMilli, 2)}`;
      row.append(number, label, estimate);
      historyList.append(row);
    });
    if (!responses.length) {
      const empty = document.createElement("li");
      empty.className = "empty";
      empty.textContent = "まだ回答はありません。";
      historyList.append(empty);
    }
  }

  function render(nextState) {
    state = nextState;
    const answered = state.responses.length;
    const ability = state.abilityMilli;
    questionCount.textContent = `${answered} / ${state.totalQuestions}`;
    questionProgress.value = answered;
    thetaValue.textContent = formatMilli(ability, 2);
    thetaMarker.style.left = `${Math.max(0, Math.min(100, (ability + 4000) / 8000 * 100))}%`;
    renderChart(state.responses, ability);
    renderHistory(state.responses);

    if (state.nextItem) {
      const item = state.nextItem;
      currentQuestion.textContent = `項目 ${item.id}`;
      itemParameters.replaceChildren();
      const values = [
        ["a", formatMilli(item.aMilli, 2)],
        ["b（難易度）", formatMilli(item.bMilli, 2)],
        ["c（当て推量）", formatMilli(item.cMilli, 2)]
      ];
      for (const [name, value] of values) {
        const chip = document.createElement("span");
        chip.className = "parameter";
        const term = document.createElement("small");
        term.textContent = name;
        const number = document.createElement("strong");
        number.textContent = value;
        chip.append(term, number);
        itemParameters.append(chip);
      }
      const probability = item.cMilli / 1000 +
        (1 - item.cMilli / 1000) /
        (1 + Math.exp(-1.7 * item.aMilli / 1000 * (ability / 1000 - item.bMilli / 1000)));
      const probabilityText = `${(probability * 100).toFixed(1)}%`;
      expectedProbability.textContent = probabilityText;
      expectedProbabilityCopy.textContent = probabilityText;
      status.textContent = "回答結果を選ぶと、能力推定を更新して次の項目を選びます。";
    } else {
      currentQuestion.textContent = "10問完了";
      itemParameters.replaceChildren();
      expectedProbability.textContent = "—";
      expectedProbabilityCopy.textContent = "—";
      status.textContent = "テストが完了しました。リセットしてもう一度試せます。";
    }
    answerButtons.forEach(button => button.disabled = !state.nextItem);
  }

  async function request(url, data) {
    const options = {cache: "no-store"};
    if (data) {
      options.method = "POST";
      options.headers = {"Content-Type": "application/x-www-form-urlencoded"};
      options.body = new URLSearchParams(data);
    }
    const response = await fetch(url, options);
    if (!response.ok) throw new Error(`通信に失敗しました (HTTP ${response.status})`);
    return response.json();
  }

  answerButtons.forEach(button => button.addEventListener("click", async () => {
    if (!state?.nextItem) return;
    error.textContent = "";
    setBusy(true);
    try {
      status.textContent = "回答を記録し、能力を再推定しています…";
      const updated = await request("/api/cat/answer", {
        itemId: String(state.nextItem.id),
        correct: button.dataset.correct
      });
      render(updated);
    } catch (failure) {
      error.textContent = failure.message;
      status.textContent = "回答を保存できませんでした。";
    } finally {
      setBusy(false);
    }
  }));

  resetButton.addEventListener("click", async () => {
    error.textContent = "";
    setBusy(true);
    try {
      status.textContent = "デモの回答履歴を初期化しています…";
      render(await request("/api/cat/reset", {}));
    } catch (failure) {
      error.textContent = failure.message;
      status.textContent = "初期化できませんでした。";
    } finally {
      setBusy(false);
    }
  });

  request("/api/cat/current").then(render).catch(failure => {
    error.textContent = failure.message;
    status.textContent = "CATデモを読み込めませんでした。";
  });
})();
</script>
"#

def main : IO Unit :=
  LeanWebStudy.Page.run fun _ =>
    pure ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
      "<meta name=\"theme-color\" content=\"#f6f7fb\">" ++
      "<title>IRT / Computerized Adaptive Testing - LeanWebStudy</title>" ++
      "<style>" ++
      "*{box-sizing:border-box}body{margin:0;background:#f6f7fb;color:#17233c;" ++
      "font-family:Inter,ui-sans-serif,system-ui,-apple-system,\"Segoe UI\",sans-serif}" ++
      "main{max-width:1080px;margin:auto;padding:28px 22px 60px}a{color:#4867dc}" ++
      ".topline{display:flex;justify-content:space-between;align-items:center;color:#68758e;" ++
      "font-size:.9rem}.topline a{text-decoration:none}.eyebrow{margin:34px 0 8px;color:#5169d8;" ++
      "font-size:.76rem;font-weight:800;letter-spacing:.14em}.intro{max-width:730px}" ++
      "h1{font-size:clamp(2rem,4vw,3rem);line-height:1.08;letter-spacing:-.04em;margin:0}" ++
      ".intro p,.muted{color:#68758e;line-height:1.65}.layout{display:grid;" ++
      "grid-template-columns:minmax(0,1.35fr) minmax(290px,.8fr);gap:18px;margin-top:24px}" ++
      ".panel{background:#fff;border:1px solid #e3e7f0;border-radius:17px;" ++
      "box-shadow:0 12px 32px #283b6810;padding:22px}.panel h2{margin:0 0 15px;font-size:1.1rem}" ++
      ".question-head{display:flex;align-items:center;justify-content:space-between;gap:12px}" ++
      ".question-number{font-size:1.55rem;font-weight:800;letter-spacing:-.03em}" ++
      ".pill{border-radius:999px;background:#eef1ff;color:#455fd0;padding:7px 11px;" ++
      "font-size:.78rem;font-weight:700;white-space:nowrap}progress{width:100%;height:8px;" ++
      "appearance:none;border:0;border-radius:10px;overflow:hidden;margin:13px 0 20px}" ++
      "progress::-webkit-progress-bar{background:#edf0f6}progress::-webkit-progress-value{" ++
      "background:#6379e7;border-radius:10px}progress::-moz-progress-bar{background:#6379e7}" ++
      ".prompt{padding:21px;border-radius:13px;background:linear-gradient(135deg,#f1f3ff,#f8f9ff);" ++
      "border:1px solid #e4e8ff}.prompt strong{font-size:1.03rem}.prompt p{margin:7px 0 0;" ++
      "color:#68758e;line-height:1.6}.parameters{display:flex;flex-wrap:wrap;gap:9px;margin:17px 0}" ++
      ".parameter{display:grid;gap:3px;min-width:100px;padding:10px 12px;border:1px solid #e7eaf1;" ++
      "border-radius:10px}.parameter small{color:#7a8497;font-size:.73rem}.parameter strong{" ++
      "font-variant-numeric:tabular-nums}.actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}" ++
      "button{font:inherit;border:0;border-radius:10px;padding:13px 14px;font-weight:750;" ++
      "cursor:pointer;transition:transform .15s,opacity .15s}button:hover:not(:disabled){" ++
      "transform:translateY(-1px)}button:disabled{opacity:.55;cursor:wait}.correct{" ++
      "background:#e8f7f0;color:#13714b}.incorrect{background:#fff0f0;color:#a23842}" ++
      ".estimate{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:12px}" ++
      ".estimate strong{font-size:2.4rem;letter-spacing:-.05em;font-variant-numeric:tabular-nums}" ++
      ".estimate small{display:block;color:#748098}.scale{position:relative;height:12px;margin:20px 4px 5px;" ++
      "border-radius:9px;background:linear-gradient(90deg,#f3d9d5,#e8ebf3 50%,#dcefe5)}" ++
      ".marker{position:absolute;top:50%;width:18px;height:18px;border:3px solid white;" ++
      "border-radius:50%;background:#526bdc;box-shadow:0 1px 5px #17233c50;transform:translate(-50%,-50%)}" ++
      ".scale-labels{display:flex;justify-content:space-between;color:#8992a3;font-size:.72rem}" ++
      ".chart{display:block;width:100%;height:auto;margin:8px 0 0;overflow:visible}" ++
      ".grid-line{stroke:#edf0f5;stroke-width:1}.axis-label{fill:#8992a3;font-size:10px}" ++
      ".theta-line{fill:none;stroke:#596fe0;stroke-width:2.5;stroke-linecap:round;" ++
      "stroke-linejoin:round}.theta-dot{fill:#596fe0;stroke:white;stroke-width:1.5}" ++
      ".submetric{display:flex;justify-content:space-between;gap:10px;padding:13px 0 0;" ++
      "border-top:1px solid #edf0f5;font-size:.87rem}.submetric span{color:#718096}" ++
      ".submetric strong{font-variant-numeric:tabular-nums}.history{list-style:none;padding:0;" ++
      "margin:0;max-height:300px;overflow:auto}.history li{display:grid;" ++
      "grid-template-columns:34px 1fr auto;align-items:center;gap:8px;padding:10px 2px;" ++
      "border-bottom:1px solid #f0f2f6;font-size:.84rem}.history-number{color:#8992a3;" ++
      "font-variant-numeric:tabular-nums}.history strong{font-variant-numeric:tabular-nums}" ++
      ".empty{display:block!important;color:#8992a3!important;padding:12px!important}" ++
      ".status{min-height:1.5em;color:#68758e;font-size:.86rem}#error{min-height:1.4em;" ++
      "color:#ad3344;overflow-wrap:anywhere;font-size:.87rem}.reset{width:100%;margin-top:13px;" ++
      "background:#f1f3f8;color:#34415a}.method{margin-top:18px;line-height:1.7}" ++
      ".formula{display:block;padding:12px 14px;background:#f7f8fb;border-radius:9px;" ++
      "font: .92rem ui-monospace,SFMono-Regular,Consolas,monospace;overflow-wrap:anywhere}" ++
      ".footnote{font-size:.82rem;color:#768197;line-height:1.65}" ++
      "@media(max-width:760px){main{padding:18px 14px 40px}.layout{grid-template-columns:1fr}" ++
      ".panel{padding:18px}.topline{align-items:flex-start}}@media(max-width:420px){" ++
      ".actions{grid-template-columns:1fr}.question-head{align-items:flex-start;flex-direction:column}}" ++
      "</style></head><body><main>" ++
      "<nav class=\"topline\"><a href=\"/\">← LeanWebStudy</a>" ++
      "<span>IRT · 3PL MODEL</span></nav>" ++
      "<header class=\"intro\"><p class=\"eyebrow\">ADAPTIVE ASSESSMENT DEMO</p>" ++
      "<h1>次の一問が、<br>あなたに合わせて変わる。</h1>" ++
      "<p>3パラメータ・ロジスティックモデル（3PL）で正答確率を計算し、" ++
      "回答のたびに受験者の能力 θ を推定。推定値に最も情報量の高い項目を選びます。</p></header>" ++
      "<div class=\"layout\"><section class=\"panel\"><div class=\"question-head\">" ++
      "<div><div class=\"muted\">現在の項目</div><div id=\"current-question\" class=\"question-number\">読み込み中…</div></div>" ++
      "<span id=\"question-count\" class=\"pill\">— / 10 問</span></div>" ++
      "<progress id=\"question-progress\" max=\"10\" value=\"0\" aria-label=\"出題の進捗\"></progress>" ++
      "<div class=\"prompt\"><strong>デモ用の項目</strong>" ++
      "<p>実際の問題文はありません。下のボタンで、この項目への回答結果を選択してください。</p></div>" ++
      "<div id=\"item-parameters\" class=\"parameters\" aria-label=\"項目パラメータ\"></div>" ++
      "<p class=\"muted\">現在の能力推定での正答確率 " ++
      "<strong id=\"expected-probability\">—</strong></p>" ++
      "<div class=\"actions\"><button class=\"correct\" type=\"button\" data-correct=\"1\">✓　正解した</button>" ++
      "<button class=\"incorrect\" type=\"button\" data-correct=\"0\">×　不正解だった</button></div>" ++
      "<p id=\"status\" class=\"status\" role=\"status\">CATデモを読み込んでいます…</p>" ++
      "<p id=\"error\" role=\"alert\"></p></section>" ++
      "<aside><section class=\"panel\"><h2>受験者の能力推定</h2>" ++
      "<div class=\"estimate\"><div><small>θ（EAP推定）</small><strong id=\"theta-value\">0.00</strong></div>" ++
      "<span class=\"pill\">事前分布 N(0, 1)</span></div>" ++
      "<div class=\"scale\"><span id=\"theta-marker\" class=\"marker\"></span></div>" ++
      "<div class=\"scale-labels\"><span>−4 低い</span><span>0</span><span>高い +4</span></div>" ++
      "<svg id=\"estimate-chart\" class=\"chart\" viewBox=\"0 0 620 130\" role=\"img\" " ++
      "aria-label=\"回答ごとの能力推定の推移\"></svg>" ++
      "<div class=\"submetric\"><span>次項目の期待正答率</span>" ++
      "<strong id=\"expected-probability-copy\">更新ごとに表示</strong></div>" ++
      "</section><section class=\"panel\" style=\"margin-top:16px\"><h2>回答履歴</h2>" ++
      "<ol id=\"history-list\" class=\"history\"></ol>" ++
      "<button id=\"reset-button\" class=\"reset\" type=\"button\">最初からやり直す</button></section></aside></div>" ++
      "<section class=\"panel method\"><h2>3PLモデルと項目選択</h2>" ++
      "<code class=\"formula\">P(θ) = c + (1 − c) / (1 + exp(−1.7a(θ − b)))</code>" ++
      "<p class=\"footnote\">a は識別力、b は難易度（項目位置）、c は当て推量の下限です。" ++
      "能力 θ は標準正規事前分布を用いた期待事後推定（EAP）で更新し、未出題項目のうち" ++
      "現在の θ でフィッシャー情報量が最大の項目を選択します。難易度 b はSQLiteに保存した" ++
      "合成プール値を表示しています。これは項目の新規校正を行う機能ではありません。</p>" ++
      "<p class=\"footnote\">項目プールは30件。回答と進捗はこのデモサーバー内のSQLiteに保存され、" ++
      "利用者間で共有されます。終了後も履歴は残ります。「最初からやり直す」で全履歴を消去します。" ++
      "本番テストや実際の評価には使用しないでください。</p></section>" ++
      client ++ "</main></body></html>")
