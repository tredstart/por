(local router (require :por.router))

(local server {})

(fn server.listen-and-serve [host port]
  (let [socket (require :socket)
        server (socket.bind host port)]
    (while true
      (let [client (server:accept)
            (line _) (client:receive :*l)
            [method path version] (router.split (or line "") " ")
            headers {}]
        (var req {})
        (set req {: method : path : version})
        (var reading true)
        (while reading
          (let [(line err) (client:receive :*l)]
            (if (not err)
                (case line
                  "" (do
                       (when (or (= req.method :POST) (= req.method :PUT)
                                 (= req.method :PATCH))
                         (let [content-len (math.tointeger (. headers
                                                              :Content-Length))]
                           (when (not= content-len 0)
                             (set req.body (client:receive content-len)))))
                       (set reading false))
                  line (let [[k v] (router.split line ": ")]
                         (set (. headers k) v))
                  _ (set reading false))
                (set reading false))))
        (set req.headers headers)
        (let [resp (router:handle-request req)]
          (client:send resp))
        (client:close)))))

server
