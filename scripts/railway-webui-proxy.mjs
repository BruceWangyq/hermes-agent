#!/usr/bin/env node
import http from 'node:http'
import net from 'node:net'

const listenPort = Number(process.env.PORT || 8080)
const webuiHost = process.env.WEBUI_UPSTREAM_HOST || '127.0.0.1'
const webuiPort = Number(process.env.WEBUI_UPSTREAM_PORT || 8648)
const gatewayHost = process.env.GATEWAY_UPSTREAM_HOST || '127.0.0.1'
const gatewayPort = Number(process.env.GATEWAY_UPSTREAM_PORT || 8642)

function pickUpstream(pathname = '/') {
  if (pathname.startsWith('/telegram')) {
    return { host: gatewayHost, port: gatewayPort, label: 'gateway' }
  }
  return { host: webuiHost, port: webuiPort, label: 'webui' }
}

function stripHopByHop(headers) {
  const next = { ...headers }
  for (const key of [
    'connection',
    'proxy-connection',
    'keep-alive',
    'transfer-encoding',
    'te',
    'trailer',
    'upgrade',
    'proxy-authenticate',
    'proxy-authorization',
  ]) {
    delete next[key]
  }
  return next
}

const server = http.createServer((req, res) => {
  const upstream = pickUpstream(req.url || '/')
  const headers = stripHopByHop(req.headers)
  headers.host = `${upstream.host}:${upstream.port}`
  headers['x-forwarded-host'] = req.headers.host || ''
  headers['x-forwarded-proto'] = 'https'
  headers['x-forwarded-for'] = req.socket.remoteAddress || ''

  const proxyReq = http.request(
    {
      host: upstream.host,
      port: upstream.port,
      method: req.method,
      path: req.url,
      headers,
    },
    (proxyRes) => {
      const responseHeaders = stripHopByHop(proxyRes.headers)
      res.writeHead(proxyRes.statusCode || 502, responseHeaders)
      proxyRes.pipe(res)
    },
  )

  proxyReq.on('error', (err) => {
    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    res.end(`Bad gateway (${upstream.label}): ${err.message}\n`)
  })

  req.pipe(proxyReq)
})

server.on('upgrade', (req, socket, head) => {
  const upstream = pickUpstream(req.url || '/')
  const target = net.connect(upstream.port, upstream.host, () => {
    let headers = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`
    for (const [key, value] of Object.entries(req.headers)) {
      if (Array.isArray(value)) {
        for (const item of value) headers += `${key}: ${item}\r\n`
      } else if (value !== undefined) {
        headers += `${key}: ${value}\r\n`
      }
    }
    headers += '\r\n'
    target.write(headers)
    if (head?.length) target.write(head)
    socket.pipe(target).pipe(socket)
  })

  target.on('error', () => socket.destroy())
  socket.on('error', () => target.destroy())
})

server.listen(listenPort, '0.0.0.0', () => {
  console.log(`[railway-webui-proxy] listening on 0.0.0.0:${listenPort}`)
  console.log(`[railway-webui-proxy] /telegram -> http://${gatewayHost}:${gatewayPort}`)
  console.log(`[railway-webui-proxy] everything else -> http://${webuiHost}:${webuiPort}`)
})
