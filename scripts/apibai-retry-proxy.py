#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
api.b.ai 本地重试中转
------------------------------------------------------------------
作用: 夹在 zcode 与第三方中转 api.b.ai 之间。
api.b.ai 会把它内部鉴权服务的临时超时伪装成 HTTP 401 返回,
而 zcode(Vercel AI SDK) 只对 408/409/429/5xx 重试、对 401 直接判失败。
本中转对这类"伪 401 / 临时故障 / 网络抖动"自动重试, 成功后原样透传
(含 SSE 流式), 连续失败到上限再把最后一次响应交回 zcode。

只监听 127.0.0.1, 上游固定 api.b.ai, 不做开放代理。
仅用 Python3 标准库, 兼容 macOS 自带 /usr/bin/python3 (3.9)。
"""

import http.server
import http.client
import ssl
import json
import time
import random
import threading
import datetime
import os
import sys
import socket

# ----------------------------- 配置 -----------------------------
UPSTREAM_HOST = "api.b.ai"          # 固定上游
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 18900                 # 本地监听端口
MAX_RETRIES = 5                     # 失败后最多再重试 5 次(首次+重试=最多6次尝试)
BASE_DELAY = 1.0                    # 首次重试前等待秒数
BACKOFF = 2.0                       # 指数退避倍数
MAX_DELAY = 12.0                    # 单次退避上限
CONNECT_TIMEOUT = 15                # 与上游建连超时
READ_TIMEOUT = 180                  # 上游读取超时(SSE 长流需要足够大)
HEALTH_PATH = "/__retry_proxy_health"

LOG_DIR = os.path.expanduser("~/.zcode/apibai-retry")
LOG_PATH = os.path.join(LOG_DIR, "retry.log")

# 明确可重试的状态码(与 zcode 内置白名单一致, 另加 425/502 等)
RETRYABLE_STATUS = {408, 409, 425, 429, 500, 502, 503, 504}

# 伪 401: body 命中这些特征说明是上游"内部服务临时故障", 值得重试
# (真正的密钥无效不会包含这些内部服务名/超时字样)
TRANSIENT_401_MARKERS = [
    "鉴权服务", "ainft-chat-service", "auth/verify",
    "context deadline", "deadline exceeded", "internal auth",
    "timeout awaiting headers", "临时", "稍后",
]

# 逐跳/需要重算的响应头, 不原样回传
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "trailers", "transfer-encoding", "upgrade", "content-length",
    "content-encoding",
}

_log_lock = threading.Lock()


def log(msg):
    line = "[%s] %s" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3], msg)
    with _log_lock:
        try:
            with open(LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except Exception:
            pass
        print(line, flush=True)


def body_is_transient_401(body_bytes):
    """判断 401 响应体是否为上游内部临时故障(而非真正的密钥错误)。"""
    try:
        txt = body_bytes.decode("utf-8", "ignore").lower()
    except Exception:
        return False
    return any(m.lower() in txt for m in TRANSIENT_401_MARKERS)


def should_retry_status(code, body_bytes):
    if code in RETRYABLE_STATUS:
        return True
    if code == 401 and body_is_transient_401(body_bytes):
        return True
    return False


def backoff_seconds(attempt):
    """attempt 从 0 开始(第 0 次重试前)。"""
    d = min(MAX_DELAY, BASE_DELAY * (BACKOFF ** attempt))
    return d + random.uniform(0, 0.4)


class RetryHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # 静默默认访问日志, 用自定义 log
    def log_message(self, fmt, *args):
        return

    # 所有 HTTP 方法统一经 __getattr__ 反射到 _handle_any

    def _handle_any(self):
        # HTTP 响应一旦开始写给 ZCode，就绝不能再重试整个请求。
        # 否则第二个 HTTP 状态行会被写进第一个 chunked body，客户端会把
        # "HTTP/1.1 ..." 当作 chunk size，报 Invalid character in chunk size。
        self._downstream_started = False

        if self.path.split("?")[0] == HEALTH_PATH:
            payload = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        # 1. 读取请求体
        length = int(self.headers.get("Content-Length", 0) or 0)
        req_body = self.rfile.read(length) if length > 0 else None

        # 2. 整理转发请求头
        fwd_headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in ("host", "content-length", "accept-encoding", "connection"):
                continue
            fwd_headers[k] = v
        fwd_headers["Host"] = UPSTREAM_HOST
        fwd_headers["Accept-Encoding"] = "identity"   # 要求明文, 便于流式透传
        if req_body is not None and "Content-Length" not in fwd_headers:
            fwd_headers["Content-Length"] = str(len(req_body))

        tag = "%s %s" % (self.command, self.path)
        last = None  # (code, headers_list, body_bytes)

        for attempt in range(MAX_RETRIES + 1):
            conn = None
            try:
                conn = http.client.HTTPSConnection(
                    UPSTREAM_HOST, 443,
                    timeout=(READ_TIMEOUT if attempt >= 0 else CONNECT_TIMEOUT),
                    context=ssl.create_default_context(),
                )
                t0 = time.time()
                conn.request(self.command, self.path, body=req_body, headers=fwd_headers)
                resp = conn.getresponse()
                code = resp.status
                ctype = resp.getheader("Content-Type", "")

                # 2xx / 3xx: 成功(或重定向), 直接流式透传, 不再重试
                if 200 <= code < 400:
                    self._stream_back(resp, code, tag, attempt, time.time() - t0)
                    return

                # 非成功: 读取(通常很小的)错误体
                err_body = resp.read(64 * 1024)
                resp_headers = list(resp.getheaders())
                last = (code, resp_headers, err_body)
                cost = time.time() - t0

                if attempt < MAX_RETRIES and should_retry_status(code, err_body):
                    wait = backoff_seconds(attempt)
                    log("%s 第%d次尝试 -> %d (%.2fs), 判定可重试, %.2fs 后重试 | %s"
                        % (tag, attempt + 1, code, cost, wait, err_body[:160].decode("utf-8", "ignore")))
                    try:
                        conn.close()
                    except Exception:
                        pass
                    time.sleep(wait)
                    continue
                else:
                    # 不可重试, 或已到上限: 把上游响应原样交回客户端
                    self._return_buffered(code, resp_headers, err_body)
                    if attempt >= MAX_RETRIES and should_retry_status(code, err_body):
                        log("%s 已重试%d次仍失败 %d, 交回客户端" % (tag, MAX_RETRIES, code))
                    else:
                        log("%s 第%d次尝试 -> %d, 不可重试(参数/密钥等), 直接透传" % (tag, attempt + 1, code))
                    return

            except (OSError, http.client.HTTPException, ssl.SSLError, socket.timeout) as e:
                last_err = repr(e)
                if self._downstream_started:
                    # 此时可能已经把部分 SSE token 发给 ZCode。重放请求会造成
                    # HTTP framing 损坏或内容重复，只能关闭当前连接，让客户端
                    # 明确感知流中断并自行决定是否重新发起完整请求。
                    self.close_connection = True
                    log("%s 下游响应已开始，随后发生异常: %s；为避免破坏 chunked 协议，不再重试并关闭连接"
                        % (tag, last_err))
                    return
                if attempt < MAX_RETRIES:
                    wait = backoff_seconds(attempt)
                    log("%s 第%d次尝试网络异常: %s, %.2fs 后重试" % (tag, attempt + 1, last_err, wait))
                    try:
                        conn and conn.close()
                    except Exception:
                        pass
                    time.sleep(wait)
                    continue
                else:
                    log("%s 网络异常且重试耗尽: %s" % (tag, last_err))
                    body = json.dumps({
                        "error": {
                            "message": "retry-proxy: upstream network failed after %d attempts: %s"
                                       % (MAX_RETRIES + 1, last_err),
                            "type": "proxy_upstream_error",
                        }
                    }).encode("utf-8")
                    self._return_buffered(502, [("Content-Type", "application/json")], body)
                    return
            finally:
                try:
                    conn and conn.close()
                except Exception:
                    pass

        # 理论兜底
        if last is not None:
            self._return_buffered(last[0], last[1], last[2])
        else:
            self._return_buffered(502, [("Content-Type", "application/json")],
                                  b'{"error":{"message":"retry-proxy: unknown failure"}}')

    # 把方法绑定上去(BaseHTTPRequestHandler 按 do_XXX 反射)
    def __getattr__(self, name):
        if name.startswith("do_"):
            return self._handle_any
        raise AttributeError(name)

    def _stream_back(self, resp, code, tag, attempt, cost):
        """成功响应: 以 chunked 流式原样回传, 不缓冲整段 body。"""
        self._downstream_started = True
        self.send_response(code)
        for k, v in resp.getheaders():
            if k.lower() in HOP_BY_HOP:
                continue
            self.send_header(k, v)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        sent = 0
        while True:
            chunk = resp.read(8192)
            if not chunk:
                break
            try:
                self.wfile.write(("%x\r\n" % len(chunk)).encode("ascii"))
                self.wfile.write(chunk)
                self.wfile.write(b"\r\n")
                self.wfile.flush()
                sent += len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                # 客户端主动断开
                log("%s 客户端在流式传输中断开, 已传%d字节" % (tag, sent))
                return
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()
        log("%s 第%d次尝试成功 %d (%.2fs), 已流式透传 %d 字节" % (tag, attempt + 1, code, cost, sent))

    def _return_buffered(self, code, headers, body):
        """非流式响应(错误/小响应)原样回传。"""
        self._downstream_started = True
        self.send_response(code)
        seen = set()
        for k, v in headers or []:
            if k.lower() in HOP_BY_HOP:
                continue
            self.send_header(k, v)
            seen.add(k.lower())
        if "content-type" not in seen:
            self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body or b"")))
        self.end_headers()
        if body:
            self.wfile.write(body)
        self.wfile.flush()


class ThreadingServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    os.makedirs(LOG_DIR, exist_ok=True)
    srv = ThreadingServer((LISTEN_HOST, LISTEN_PORT), RetryHandler)
    log("api.b.ai 重试中转已启动: http://%s:%d -> https://%s (最多重试%d次)"
        % (LISTEN_HOST, LISTEN_PORT, UPSTREAM_HOST, MAX_RETRIES))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log("收到中断, 退出")
        srv.shutdown()


if __name__ == "__main__":
    main()
