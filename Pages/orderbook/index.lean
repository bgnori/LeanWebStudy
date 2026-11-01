import LeanWebStudy.Page

private def client : String := r#"
<script>
(() => {
  const form = document.getElementById("order-form");
  const bids = document.getElementById("bids");
  const asks = document.getElementById("asks");
  const trades = document.getElementById("trades");
  const chart = document.getElementById("price-chart");
  const chartEmpty = document.getElementById("chart-empty");
  const status = document.getElementById("status");
  const error = document.getElementById("error");
  const svgNamespace = "http://www.w3.org/2000/svg";

  function priceText(cents) {
    return (cents / 100).toFixed(2);
  }

  function levelsFor(orders, side) {
    const levels = new Map();
    for (const order of orders) {
      if (order.side !== side) continue;
      levels.set(order.price, (levels.get(order.price) || 0) + order.remaining);
    }
    return [...levels].sort((a, b) => side === "buy" ? b[0] - a[0] : a[0] - b[0]);
  }

  function renderLevels(list, levels, maxQuantity, side) {
    list.replaceChildren();
    const displayed = side === "sell" ? [...levels].reverse() : levels;
    if (!displayed.length) {
      const empty = document.createElement("li");
      empty.className = "empty";
      empty.textContent = "注文なし";
      list.append(empty);
      return;
    }
    for (const [price, quantity] of displayed) {
      const row = document.createElement("li");
      row.className = "level";
      const bar = document.createElement("span");
      bar.className = "depth";
      bar.style.width = `${Math.max(3, quantity / maxQuantity * 100)}%`;
      const value = document.createElement("strong");
      value.textContent = priceText(price);
      const amount = document.createElement("span");
      amount.textContent = quantity.toLocaleString();
      row.append(bar, value, amount);
      list.append(row);
    }
  }

  function svgElement(name, attributes = {}) {
    const element = document.createElementNS(svgNamespace, name);
    for (const [key, value] of Object.entries(attributes))
      element.setAttribute(key, value);
    return element;
  }

  function candlesFor(history) {
    const bucketSize = Math.max(2, Math.ceil(history.length / 10));
    const candles = [];
    for (let index = 0; index < history.length; index += bucketSize) {
      const prices = history.slice(index, index + bucketSize).map(trade => trade.price);
      candles.push({
        open: prices[0],
        high: Math.max(...prices),
        low: Math.min(...prices),
        close: prices[prices.length - 1]
      });
    }
    return candles;
  }

  function renderChart(history) {
    chart.replaceChildren();
    if (!history.length) {
      chart.hidden = true;
      chartEmpty.hidden = false;
      return;
    }
    chart.hidden = false;
    chartEmpty.hidden = true;
    const candles = candlesFor(history);
    const width = 760;
    const height = 250;
    const plot = {left: 58, right: 14, top: 16, bottom: 30};
    const prices = candles.flatMap(candle => [candle.high, candle.low]);
    let minimum = Math.min(...prices);
    let maximum = Math.max(...prices);
    const padding = Math.max(5, Math.ceil((maximum - minimum) * 0.15));
    minimum -= padding;
    maximum += padding;
    const y = price => plot.top +
      (maximum - price) / (maximum - minimum) * (height - plot.top - plot.bottom);
    const plotWidth = width - plot.left - plot.right;
    const slotWidth = plotWidth / candles.length;

    for (let line = 0; line <= 4; line++) {
      const value = maximum - (maximum - minimum) * line / 4;
      const lineY = plot.top + (height - plot.top - plot.bottom) * line / 4;
      chart.append(svgElement("line", {
        x1: plot.left, x2: width - plot.right, y1: lineY, y2: lineY, class: "grid-line"
      }));
      const label = svgElement("text", {
        x: plot.left - 8, y: lineY + 4, class: "axis-label", "text-anchor": "end"
      });
      label.textContent = priceText(Math.round(value));
      chart.append(label);
    }

    candles.forEach((candle, index) => {
      const x = plot.left + slotWidth * (index + 0.5);
      const rising = candle.close >= candle.open;
      const className = rising ? "candle-up" : "candle-down";
      chart.append(svgElement("line", {
        x1: x, x2: x, y1: y(candle.high), y2: y(candle.low), class: `wick ${className}`
      }));
      const bodyTop = Math.min(y(candle.open), y(candle.close));
      const bodyHeight = Math.max(2, Math.abs(y(candle.open) - y(candle.close)));
      chart.append(svgElement("rect", {
        x: x - Math.min(14, slotWidth * 0.28),
        y: bodyTop,
        width: Math.min(28, slotWidth * 0.56),
        height: bodyHeight,
        rx: 1,
        class: className
      }));
      const label = svgElement("text", {
        x, y: height - 9, class: "axis-label", "text-anchor": "middle"
      });
      label.textContent = String(index + 1);
      chart.append(label);
    });
  }

  function render(book) {
    const bidLevels = levelsFor(book.orders, "buy");
    const askLevels = levelsFor(book.orders, "sell");
    const maxQuantity = Math.max(1, ...[...bidLevels, ...askLevels].map(level => level[1]));
    renderLevels(asks, askLevels, maxQuantity, "sell");
    renderLevels(bids, bidLevels, maxQuantity, "buy");
    trades.replaceChildren();
    const chronological = [...book.trades];
    const recent = [...chronological].reverse();
    renderChart(chronological);
    if (!recent.length) {
      const empty = document.createElement("li");
      empty.className = "empty";
      empty.textContent = "約定履歴はありません";
      trades.append(empty);
    }
    for (const trade of recent) {
      const row = document.createElement("li");
      const price = document.createElement("strong");
      price.textContent = priceText(trade.price);
      const quantity = document.createElement("span");
      quantity.textContent = `${trade.quantity.toLocaleString()} 枚`;
      const ids = document.createElement("small");
      ids.textContent = `maker #${trade.makerOrderId} · taker #${trade.takerOrderId}`;
      row.append(price, quantity, ids);
      trades.append(row);
    }
    const bestBid = bidLevels[0]?.[0];
    const bestAsk = askLevels[0]?.[0];
    document.getElementById("spread").textContent =
      bestBid === undefined || bestAsk === undefined ? "—"
        : `${priceText(bestAsk - bestBid)} USD`;
    document.getElementById("market").textContent =
      bestBid === undefined || bestAsk === undefined ? "気配値なし"
        : `${priceText(bestBid)} / ${priceText(bestAsk)}`;
    document.getElementById("order-count").textContent =
      `${book.orders.length} 件の注文 · 直近 ${recent.length} 件の約定`;
  }

  async function loadBook() {
    const response = await fetch("/api/orderbook", {cache: "no-store"});
    if (!response.ok) throw new Error(`注文板の取得に失敗しました (HTTP ${response.status})`);
    render(await response.json());
    status.textContent = "注文を入力できます。";
  }

  form.addEventListener("submit", async event => {
    event.preventDefault();
    error.textContent = "";
    status.textContent = "注文を送信しています…";
    const button = form.querySelector("button[type=submit]");
    button.disabled = true;
    try {
      const response = await fetch("/api/orderbook/orders", {
        method: "POST",
        headers: {"Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"},
        body: new URLSearchParams(new FormData(form))
      });
      if (!response.ok) {
        const detail = await response.text();
        throw new Error(detail.trim() || `注文に失敗しました (HTTP ${response.status})`);
      }
      const result = await response.json();
      render(result.book);
      status.textContent = result.trades.length
        ? `注文 #${result.orderId} は ${result.trades.length} 件に分かれて約定しました。`
        : `注文 #${result.orderId} を注文板に登録しました。`;
      if (result.remaining > 0 && result.trades.length)
        status.textContent += ` 残り ${result.remaining} 枚は注文板に残っています。`;
      form.elements.quantity.value = "";
    } catch (failure) {
      error.textContent = failure.message;
      status.textContent = "注文を処理できませんでした。";
    } finally {
      button.disabled = false;
    }
  });

  loadBook().catch(failure => {
    error.textContent = failure.message;
    status.textContent = "注文板を読み込めませんでした。";
  });
})();
</script>
"#

def main : IO Unit :=
  LeanWebStudy.Page.run fun _ =>
    pure ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
      "<meta name=\"theme-color\" content=\"#f4f6fb\">" ++
      "<title>Limit Order Book - LeanWebStudy</title>" ++
      "<style>body{font-family:system-ui,sans-serif;background:#f4f6fb;color:#17243b;margin:0}" ++
      "main{max-width:1000px;margin:auto;padding:24px}a{color:#315bd6}" ++
      ".panel{background:white;border:1px solid #e1e7f0;border-radius:14px;padding:20px;margin:18px 0}" ++
      ".market-grid{display:grid;grid-template-columns:minmax(0,1.2fr) minmax(300px,.8fr);" ++
      "gap:18px;align-items:start}.book-panel{margin:0}.book-header{display:flex;align-items:baseline;" ++
      "justify-content:space-between;gap:12px}.book-header h2{margin:0}.book-header p{margin:0}" ++
      ".column-labels,.level{display:grid;grid-template-columns:1fr 1fr;gap:12px;" ++
      "font-variant-numeric:tabular-nums}.column-labels{padding:8px 10px;color:#718096;" ++
      "font-size:.8rem;border-bottom:1px solid #e4e9f1}.column-labels span:last-child," ++
      ".level span:last-child{text-align:right}.levels,.fills{list-style:none;padding:0;margin:0}" ++
      ".level{position:relative;padding:8px 10px;overflow:hidden;min-height:1.25rem}" ++
      ".level .depth{position:absolute;inset:2px 0 2px auto;opacity:.14;pointer-events:none}" ++
      "#bids .depth{background:#17845e}#asks .depth{background:#d24b55}" ++
      ".level span:not(.depth),.level strong{position:relative}.level strong{font-weight:650}" ++
      "#bids strong{color:#087650}#asks strong{color:#b82f3d}.spread{margin:5px 0;padding:11px 10px;" ++
      "display:flex;justify-content:space-between;align-items:center;border-top:1px solid #dbe2ec;" ++
      "border-bottom:1px solid #dbe2ec;background:#f3f6fa;font-variant-numeric:tabular-nums}" ++
      ".spread strong{font-size:1.05rem}.spread small{color:#627087}.side-panel{display:grid;gap:18px}" ++
      ".side-panel .panel{margin:0}.chart-wrap{position:relative;min-height:250px}.chart{" ++
      "display:block;width:100%;height:auto}.grid-line{stroke:#e3e8f0;stroke-width:1}" ++
      ".axis-label{fill:#6d798b;font-size:11px;font-family:system-ui,sans-serif}" ++
      ".wick{stroke-width:2}.candle-up{fill:#15805d;stroke:#15805d}.candle-down{" ++
      "fill:#d14954;stroke:#d14954}.chart-empty{position:absolute;inset:0;display:grid;" ++
      "place-items:center;text-align:center;color:#718096;padding:30px}.chart-empty[hidden]{" ++
      "display:none}.form-grid{display:grid;" ++
      "grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.form-grid label{display:block;" ++
      "font-weight:600;margin-bottom:6px}input,select,button{box-sizing:border-box;width:100%;" ++
      "padding:11px;font:inherit;border:1px solid #ccd5e2;border-radius:7px}button{margin-top:16px;" ++
      "background:#315bd6;color:white;border:0;font-weight:700;cursor:pointer}button:disabled{" ++
      "opacity:.6;cursor:wait}.fills li{display:grid;grid-template-columns:1fr 1fr auto;" ++
      "gap:12px;padding:10px 0;border-bottom:1px solid #edf0f5;font-variant-numeric:tabular-nums}" ++
      ".fills small{color:#627087}.empty{color:#718096;padding:10px}#error{color:#a51c30;" ++
      "white-space:pre-wrap;overflow-wrap:anywhere;min-height:1.5em}#status{min-height:1.5em}" ++
      ".note{color:#56657c;font-size:.95rem;line-height:1.6}@media(max-width:760px){" ++
      "main{padding:16px}.market-grid{grid-template-columns:1fr}.panel{padding:15px}" ++
      ".form-grid{grid-template-columns:1fr}.fills li{grid-template-columns:1fr auto}" ++
      ".fills small{grid-column:1/-1}}</style></head><body><main>" ++
      "<p><a href=\"/\">LeanWebStudy</a></p><h1>Limit Order Book / Matching Engine</h1>" ++
      "<p>指値注文を出し、価格優先・時間優先で自動マッチングする学習用デモです。</p>" ++
      "<section class=\"panel\"><h2>注文を出す</h2><form id=\"order-form\">" ++
      "<div class=\"form-grid\"><div><label for=\"side\">売買</label>" ++
      "<select id=\"side\" name=\"side\"><option value=\"buy\">買い (Bid)</option>" ++
      "<option value=\"sell\">売り (Ask)</option></select></div>" ++
      "<div><label for=\"price\">指値価格 (USD)</label>" ++
      "<input id=\"price\" name=\"price\" type=\"number\" min=\"0.01\" max=\"1000000\" " ++
      "step=\"0.01\" value=\"101.00\" required></div>" ++
      "<div><label for=\"quantity\">数量</label>" ++
      "<input id=\"quantity\" name=\"quantity\" type=\"number\" min=\"1\" max=\"1000000\" " ++
      "step=\"1\" placeholder=\"例: 5\" required></div></div>" ++
      "<button type=\"submit\">注文を送信</button></form><p id=\"status\" role=\"status\">" ++
      "注文板を読み込んでいます…</p><p id=\"error\" role=\"alert\"></p></section>" ++
      "<div class=\"market-grid\"><section class=\"panel book-panel\">" ++
      "<div class=\"book-header\"><h2>注文板</h2><p id=\"order-count\" class=\"note\"></p></div>" ++
      "<div class=\"column-labels\"><span>価格 (USD)</span><span>数量</span></div>" ++
      "<ol id=\"asks\" class=\"levels\" aria-label=\"売り注文\"></ol>" ++
      "<p class=\"spread\"><span><small>スプレッド</small><br><strong id=\"spread\">—</strong></span>" ++
      "<span><small>最良気配 (Bid / Ask)</small><br><strong id=\"market\">—</strong></span></p>" ++
      "<ol id=\"bids\" class=\"levels\" aria-label=\"買い注文\"></ol></section>" ++
      "<div class=\"side-panel\"><section class=\"panel\"><h2>約定価格チャート</h2>" ++
      "<p class=\"note\">直近の約定を2件以上ずつ、最大10区間にまとめたOHLCです。横軸は約定順です。</p>" ++
      "<div class=\"chart-wrap\"><svg id=\"price-chart\" class=\"chart\" viewBox=\"0 0 760 250\" " ++
      "role=\"img\" aria-label=\"約定価格のローソク足チャート\"></svg>" ++
      "<p id=\"chart-empty\" class=\"chart-empty\">約定が発生するとローソク足を表示します。</p>" ++
      "</div></section><section class=\"panel\"><h2>直近の約定</h2>" ++
      "<ul id=\"trades\" class=\"fills\"></ul></section></div></div>" ++
      "<p class=\"note\">価格は1セント単位、数量は整数で扱います。注文はプロセスメモリー上に保持し、" ++
      "再起動で初期状態に戻ります。デモ用の単一注文板で、認証・残高確認・キャンセル・" ++
      "永続化・実際の取引機能はありません。実運用には使用しないでください。</p></main>" ++
      client ++ "</body></html>")
