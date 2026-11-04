import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>LeanWebStudy</title></head><body><h1>LeanWebStudy</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<h2>習作</h2><ul>" ++
        "<li><a href=\"/sqlite/\">MapleSQLで操作するSQLite</a></li>" ++
        "<li><a href=\"/templates/\">lean-htmlテンプレート</a></li>" ++
        "<li><a href=\"/board/\">掲示板 Webアプリ</a></li>" ++
        "<li><a href=\"/wiki/\">Wiki Webアプリ</a></li>" ++
        "<li><a href=\"/orderbook/\">Limit Order Book / Matching Engine</a></li>" ++
        "<li><a href=\"/cat/\">IRT / Computerized Adaptive Testing デモ</a></li>" ++
        "<li><a href=\"/shop/\">niwa store - ECサイトのページ遷移デモ</a></li>" ++
        "<li><a href=\"/chat/\">WebSocket リアルタイムチャット</a></li>" ++
        "<li><a href=\"/chat-ws/\">WebSocket チャット (ws-lean)</a></li>" ++
        "<li><a href=\"/chat-same-port/\">WebSocket チャット (same-port-websocket)</a></li>" ++
        "<li><a href=\"/chat-sse/\">SSE リアルタイムチャット</a></li>" ++
        "<li><a href=\"/pong/\">WebSocket 通信対戦 Pong</a></li>" ++
        "</ul></body></html>")
