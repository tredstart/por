(local router (require :por.router))

(local server {})

(fn server.listen-and-serve [host port]
  (let [socket (require :socket)
        server (socket.bind host port)]
    (while true
      (let [client (server:accept)
            req {}]
        (var reading true)
        (while reading
          (let [(line err) (client:receive :*l)]
            (if (not err)
                (if (or (not line) (= line ""))
                    (set reading false)
                    (table.insert req line))
                (set reading false))))
        (let [resp (router:handle-request req)]
          (client:send resp))
        (client:close)))))

server
