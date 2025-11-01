(local router (require :por.router))
(local socket (require :socket))
(local m {})

(fn read-request [client]
  "Reads request line by line. Expects a client connection. If request method
  is `post`, `patch` or `put`, checks for the content length header first and
  if it has more than 0 bytes tries to read them into `req.body`."
  (let [(line err) (client:receive :*l)]
    (when (not err)
      (let [[method path version] (router.split (or line "") " ")
            headers {}
            req {: method : path : version}]
        (var reading true)
        (while reading
          (case (client:receive :*l)
            "" (do
                 (when (or (= req.method :POST) (= req.method :PUT)
                           (= req.method :PATCH))
                   (let [content-len (tonumber (. headers :Content-Length))]
                     (when (and content-len (not= content-len 0))
                       (let [(body err) (client:receive content-len)]
                         (if (not err)
                             (set req.body body)
                             (set reading false))))))
                 (when reading
                   (set reading false)))
            line (let [[k v] (router.split line ": ")]
                   (set (. headers k) v))
            ?err (do
                   (router.view :error-case ?err)
                   (set reading false))))
        (set req.headers headers)
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
