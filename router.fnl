(local http/errors (require :por.templates))

(fn view [...]
  "Helper function print out contents of the table.
  Example: 
  ```
  (view \"check the value of the t\" [:hello :world])
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  value t: 1 \"check the value of the t\"
  value t: 2 [:hello :world]
  ```"
  (let [args [...]]
    (each [i t (ipairs args)]
      (print "value t:" i " " ((. (require :fennel) :view) t)))))

(fn response [status-code status content-type content]
  "Generic response function. Return a string containing http response"
  (.. "HTTP/1.1 " status-code " " status "\r\nContent-Type: " content-type "; charset=utf-8\r
"
      "Content-Length: " (length content) "\r\n" "\r\n" content))

(fn response/redirect [status-code status location]
  "Generic redirect. Same as `response`."
  (.. "HTTP/1.1 " status-code " " status "\r\nLocation: " location "\r
Content-Type: text/html; charset=utf-8\r
"))

(fn safe [str]
  "Unescaping the string."
  (when str
    (-> str
        (string.gsub "+" " ")
        (string.gsub "%%(%x%x)"
                     (fn [hex]
                       (string.char (tonumber hex 16)))))))

(fn response/html [status-code status content]
  "Respond with an html.
  @params
  status-code number
  status string
  content string"
  (response status-code status :text/html content))

(fn response/template [content]
  "Respond with a successful render of the template. Expects a string to respond with. Always sends 200 :OK"
  (response/html 200 :OK content))

(fn content-or-error [file-path content-type]
  "If the file is found and can be read returns a string with contents of it. Else returns a template for 404."
  (var content "")
  (local (ok err) (pcall #(with-open [file (io.open file-path :r)]
                            (set content (file:read :*all)))))
  (case ok
    true (response 200 :OK content-type content)
    false (do
            (print "ERROR READING FILE" file-path err)
            (http/errors.not-found))))

(fn response/static [r path]
  "Returns the string with the content of the file. If not found return 404."
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
  "Checks the string for {wildcards}"
  (icollect [m (string.gmatch s "{[%w-_]+}")]
    m))

(fn find-masked [original masked]
  "Looks for {mask} and tries to match it. Returns a seq table with matched values."
  (var pattern (string.gsub masked "{[%w_-]+}" "\000CARD\000"))
  (set pattern (string.gsub pattern "([%^%$%(%)%%%.%[%]%*%+%-%?])" "%%%1"))
  (set pattern (string.gsub pattern "\000CARD\000" "(.-)"))
  (set pattern (.. "^" pattern "$"))
  [(string.match original pattern)])

(fn walk-url [routes url path-params]
  "@params
  routes a table of all registered routes with their handlers and wildcards
  url list of possible route nodes (example: [\"path/\" \"to/\" \"blog/\"])
  path-params is a table of potential parameters extracted from wildcards and their respective values"
  (let [[path & rest] url]
    (case [(. routes path) rest]
      ;; Happy path. We are at the last node and we try to return a handler.
      ;; If the handler is nil then `handle-request`
      ;; will return 404.
      [route [nil]]
      [(. route :handler) path-params]
      ;; Happy path. We hit the existing node but url has more to go so we recurse deeper into the routes tree.
      [route & [rest]]
      (walk-url route rest path-params)
      ;; Unhappy path. We don't have this specific node but we still want to try for the wildcards on this path.
      [nil _]
      ;; Accumulate will return the value of found and we set found only if we have hit the first happy path.
      ;; Otherwise it will always stay nil and so we'll get 404.
      (accumulate [found nil r _ (pairs routes)]
        (or found
            (when (and (= (r:sub -1 -1) "/")
                       (not= (length (. routes r :wildcards)) 0))
              ;; When the we hit the route key (key that ends with "/") and it has wildcards
              ;; Try to match current path to our route
              ;; Example of correct match "hello-world/" "hello-{who}/" -> ["who"]
              (let [m (find-masked path r)
                    wildcards (. routes r :wildcards)]
                ;; If the number of matched values is the same as number of wildcards on this route, means we found
                ;; the correct route
                (when (= (length m) (length wildcards))
                  ;; create temporary local-params so if we hit the wrong route that had similar pattern
                  ;; we don't have to remove things from path-params
                  (let [local-params (collect [k v (pairs path-params)]
                                       (values k v))]
                    (each [i card (ipairs wildcards)]
                      ;; set values for all wildcards
                      (tset local-params (card:sub 2 -2) (. m i)))
                    ;; check this route (r) again with the rest
                    (walk-url routes [r (table.unpack rest)] local-params))))))))))

(fn build-route [r url handler]
  "Recursively builds routes and sets handlers/wildcards."
  (let [[key & rest] url
        wildcards (find-wildcards key)]
    (when (not (. r key)) (set (. r key) {}))
    (set (. r key :wildcards) wildcards)
    (case rest
      [nil] (set (. r key :handler) handler)
      _ (build-route (. r key) rest handler))))

(fn split [str ?sep]
  "Split a string using a separator. If split by `/` it will return an array with items ending on `/`. 
  It's a design choice. If you don't agree with it - write it on paper, pack it into envelope and throw it out 
  of your window. By default it splits by spaces."
  (case ?sep
    "/" (let [result ["/"]]
          (icollect [s (string.gmatch str "[^/]+") &into result]
            (.. s "/")))
    nil (icollect [s (string.gmatch str "[^ ]+")]
          s)
    _ (icollect [s (string.gmatch str (.. "[^" ?sep "]+"))]
        s)))

(fn register [r method path handler]
  "Register a route. Handler should be a callable function that might accept `req` and `path-params` tables."
  (when (not (. r.routes method))
    (set (. r.routes method) {}))
  (let [url (split path "/")]
    (build-route (. r.routes method) url handler)))

(fn try-read-body [body]
  "If the body exists, split it into key value pairs"
  (when body
    (let [items (split body "&")]
      (collect [_ item (ipairs items)]
        (let [[k v] (split item "=")] (values k v))))))

(fn handle-request [r req]
  "Try to handle any given request"
  (let [[method path] [(. req :method) (. req :path)]
        url (split path "/")
        routes (. r.routes method)]
    (set req.form (try-read-body (. req :body)))
    (if (and (= method :GET) (string.match path r.static-url))
        (response/static r path)
        (if routes
            (let [result (walk-url routes url {})]
              (case result
                [handler params] (handler req params)
                _ (http/errors.not-found)))
            (http/errors.method-not-allowed)))))

{:routes {}
 :static-url :^/static/
 :static-path :./static/
 : register
 : handle-request
 : response
 : response/static
 : response/html
 : response/template
 : view
 : split
 : response/redirect
 : safe}
