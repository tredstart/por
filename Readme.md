# Por. [WIP]

Minimalistic web framework written in `Fennel`.

## Reasoning

I wanted to use `lua` on backend but had trouble (so called skill issues) to
run and install `lapis/openresty` on every platform I needed due to `Lua` version incompatibilities (`Nix` probably
fixes this). Also, apparently, I love `lisp` now.

## Requirements
- `lua >= 5.2`
- `luasocket`
- **(optional)** `lsqlite3` (if you want to use `garden`)

## Usage
### Framework
Starting and running a server is easy:
```fennel
(local {: server : router : garden} (require :por))
(local {: form : input : div} (require :por.leaf))

;; Garden is a little sqlite3 helper
(garden:setup :test.db)

;; Register expects method, path, and a handler (function) that returns a string with a response
(router:register :GET "/" (fn [_] (router.response 200 :OK :text/plain "Hello, World!")))

;; You can also use {wildcards} that will be passed as a parameter to the handler
(router:register :GET "/hello-{who}"
                 (fn [_ params]
                   (router.response 200 :OK :text/plain
                                    (.. "Hello, " params.who "!"))))

;; You can also use "leaf" templating
(router:register :GET "/post-{id}"
                 (fn [_ params]
                   (router.response/template (div {:id (.. :post- id) (form (input {:name :post-name})
                                                        (input {:type :submit}))))))

;; The first param passed to the handler contains request {: method : path : version : headers : body : form}
;; where form might be nil if body of the request was empty or couldn't be parsed.
;; body is raw request body.
;; headers is a table of all headers passed on the request
(router:register :PATCH "/post-{id}"
                 (fn [req params] (update-post params.id req.form.name)
                   (response 200 :OK :text/plain :Success)))


;; Then you start a server on host and port
(server.listen-and-serve :localhost :6969)
(garden:close)
```

### Router

```fennel

{;; Table of all registered routes
 :routes {}
 ;; This url can be changed but based on it, any static responses will be handled
 :static-url :^/static/
 ;; This is a path to static files
 :static-path :./static/
 ;; Register a route
 : register
 : handle-request
 ;; Simplest, most customizable response
 : response
 ;; Respond with a file
 : response/static
 ;; Response with a status-code status and html
 : response/html
 ;; Responde with 200 :OK and some content
 : response/template
 ;; Helper function that lets you view content of tables
 : view
 ;; A weird split
 : split
 ;; Simplest redirect
 : response/redirect
 ;; Make weird symbols into readable symbols (unescape)
 : safe}
```

More is described in the router.fnl

### Leaf

Leaf is basically html in fennel.

```fennel
;; import it like this for ease of use anywhere

(local {: html : head : title : body : div : h1 : ul : li : img} (require :por.leaf))

;; and because it's just regular fennel functions you can use it inside fennel code

(fn index []
  (html
    (head
      (title "My super web framework"))
    (body
      ;; if the first element of the tag is a table it is treated like argument table for the tag
      ;; so you can pass classes, ids, source or anything else here just like it's plain html
      (div {:class :container}
        (h1 "Hello, world!")
        (img {:id :awesome-image :src :/static/assets/screenshot.png :alt "My wholesome screenshot"})
        (ul
          ;; no really, you're dealing with fennel functions that return just strings
          (accumulate [result "" name title (pairs users)]
            (.. result (li ( .. name " " title)))))))))
```

### Garden

In future it will become an sql builder but for now it's a simple set of queries:
- select
- insert
- update
- delete
Additionally you have
- join
- where
that you can use for select.

Example:
```fennel
{:list-all-orders (fn [] (db:select "*" :orders))
 :get-order-items (fn [id]
                    (db:select "oi.id, i.name, i.link,
                         oi.amount AS order_amount"
                               "items i"
                               (db.join "order_items oi" "oi.item_id = i.id")
                               (db.where (.. "oi.order_id = " id))))
 :get-order-item (fn [id]
                   (db:select "oi.id, i.name, i.link, oi.amount" "items i"
                              (db.join "order_items oi" "oi.item_id = i.id")
                              (db.where (.. "oi.id =" id))))
 :create-order (fn [date status]
                 (db:insert "orders (date, status)"
                            (.. "\"" date "\"" ", " "\"" status "\"")))
 :list-item-amounts (fn [id]
                      (db:select "i.id, i.amount,
                         oi.amount AS order_amount"
                                 "items i"
                                 (db.join "order_items oi" "oi.item_id = i.id")
                                 (db.where (.. "oi.order_id = " id))))
 :update-status (fn [id status]
                  (db:update :orders (.. "status = \"" status "\"")
                             (.. "id = " id)))
 :get-last-order (fn []
                   (db:select :id :orders
                              (db.where (.. "status = \"" (. order-status 1)
                                            "\""))))
 :get-order (fn [id]
              (db:select "*" :orders (db.where (.. "id = " id))))
 :add-to-order (fn [id item-id]
                 (db:insert "order_items (order_id, item_id)"
                            (.. id ", " item-id)))
 :update-order-item (fn [id amount]
                      (db:update :order_items (.. "amount = " amount)
                                 (.. "id = " id)))
 :delete-item (fn [id]
                (db:delete :order_items (.. "id = " id)))
```

For now, as you can see, most of the sql you'd have to write yourself still, but
in future iterations of this project, hopefully this can be eliminated.  
  
Best of luck.
