; FIXME: this
(local http/errors (require :por.templates.not-found))

(fn view [...]
  (let [args [...]]
    (each [i t (ipairs args)]
      (print "value t:" i " " ((. (require :fennel) :view) t)))))

(view http/errors)

(fn response [status-code status content-type content]
  (.. "HTTP/1.1 " status-code " " status "\r\nContent-Type: " content-type "; charset=utf-8\r
"
      "Content-Length: " (length content) "\r\n" "\r\n" content))

(fn content-or-error [file-path content-type]
  (var content "")
  (local (ok err) (pcall #(with-open [file (io.open file-path :r)]
                            (set content (file:read :*all)))))
  (case ok
    true (response 200 :OK content-type content)
    false (do
            (print err)
            (http/errors.not-found))))

(fn response/static [r path]
  (let [file-path (string.gsub path r.static-url r.static-path)
        content-type (case (string.match path "%.(%w+)$")
                       :css :text/css
                       :js :application/javascript
                       :txt :text/plain
                       :png :image/png
                       :jpg :image/jpeg
                       :gif :image/gif
                       :svg :image/svg+xml
                       _ :application/octet-stream)]
    (content-or-error file-path content-type)))

(fn find-wildcards [s]
  (icollect [m (string.gmatch s "{[%w-_]+}")]
    m))

(fn find-masked [original masked]
  (var pattern (string.gsub masked "([%^%$%(%)%%%.%[%]%*%+%-%?])" "%%%1"))
  (set pattern (string.gsub pattern "{[%w-_]+}" "(.-)"))
  (set pattern (.. "^" pattern "$"))
  [(string.match original pattern)])

(fn walk-url [routes url path-params]
  (let [[path & rest] url]
    (view :walk-url (. routes path) rest)
    (case [(. routes path) rest]
      [route [nil]] (. route :handler)
      [route & [rest]] (walk-url route rest path-params)
      [nil _] (accumulate [found nil r _ (pairs routes)]
                (or found
                    (when (and (= (r:sub -1 -1) "/")
                               (not= (length (. routes r :wildcards)) 0))
                      (view :found (. routes r :wildcards))
                      (let [m (find-masked path r)
                            wildcards (. routes r :wildcards)]
                        (when (= (length m) (length wildcards))
                          (collect [i card (ipairs wildcards) &into path-params]
                            (values (card:sub 2 -2) (. m i)))
                          (view :path-params path-params r)
                          (walk-url routes [r (table.unpack rest)] path-params)))))))))

(fn build-route [r url handler]
  (case url
    [key nil] (do
                (when (not (. r key)) (set (. r key) {}))
                (set (. r key) {:wildcards (find-wildcards key) : handler}))
    [key & rest] (let [wildcards (find-wildcards key)]
                   (when (not (. r key)) (set (. r key) {}))
                   (set (. r key :wildcards) wildcards)
                   (build-route (. r key) rest handler))))

(fn split [str ?sep]
  (case ?sep
    "/" (let [result ["/"]]
          (icollect [s (string.gmatch str "[^/]+") &into result]
            (.. s "/")))
    nil (icollect [s (string.gmatch str "[^ ]+")]
          s)
    _ (icollect [s (string.gmatch str (.. "[^" ?sep "]+"))]
        s)))

(fn register [r method path handler]
  (when (not (. r.routes method))
    (set (. r.routes method) {}))
  (let [url (split path "/")]
    (build-route (. r.routes method) url handler)))

(fn handle-request [r req]
  (let [[request-line & _] req
        [method path] (split request-line)
        url (split path "/")
        routes (. r.routes method)]
    (view :handle-request method path url)
    (if (and (= method :GET) (string.match path r.static-url))
        (do
          (view "status~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
                r path)
          (response/static r path))
        (let [params {}]
          (or (let [handler (walk-url routes url params)]
                (and handler (handler req params)))
              (http/errors.not-found))))))

{:routes {}
 :static-url :^/static/
 :static-path :./static/
 : register
 : handle-request
 : response/static
 : response}
