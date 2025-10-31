(local router (require :por.router))
(local socket (require :socket))
(local m {})

(fn read-request [client]
  (let [(line err) (client:receive :*l)]
    (when (not err)
      (let [[method path version] (router.split (or line "") " ")
            headers {}
            req {: method : path : version}]
        (var reading true)
        (var complete false)
        (while reading
          (case (client:receive :*l)
            ["" nil] (do
                       (when (or (= req.method :POST) (= req.method :PUT)
                                 (= req.method :PATCH))
                         (let [content-len (tonumber (. headers :Content-Length))]
                           (when (and content-len (not= content-len 0))
                             (let [(body err) (client:receive content-len)]
                               (if (not err)
                                   (set req.body body)
                                   (set reading false))))))
                       (when reading
                         (set reading false)
                         (set complete true)))
            [line nil] (let [[k v] (router.split line ": ")]
                         (set (. headers k) v))
            _ (set reading false)))
        (set req.headers headers)
        (router.view "are we happening complete" req complete)
        req))))

(fn m.listen-and-serve [host port]
  (let [server (socket.bind host port)
        clients {}]
    (while true
      (let [recvt (socket.select clients nil 0)]
        (server:settimeout 0)
        (let [client (server:accept)]
          (when client (table.insert clients client)))
        (when (> (length recvt) 0)
          (each [_ sock (ipairs recvt)]
            (let [req (read-request sock)]
              (when req
                (sock:send (router:handle-request req))))
            (sock:close)))))))

m
