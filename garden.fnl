(local db (require :lsqlite3))

; TODO: add error handling

(local m {})

(fn m.setup [self db-name]
  (set self.connection (db.open db-name)))

(fn m.close [self]
  (db.close self.connection))

(fn m.run [self query]
  (db.exec self.connection query))

(fn m.select [self what from ...]
  (let [sql (.. "SELECT " what " FROM " from
                (let [clauses [...]]
                  (accumulate [result "" _ clause (ipairs clauses)]
                    (.. result clause))) ";")
        result []]
    (print :select (self.connection:exec sql
                                         (fn [_ cols v n]
                                           (table.insert result
                                                         (faccumulate [t {} i 1 cols]
                                                           (let [new-t t]
                                                             (set (. t (. n i))
                                                                  (. v i))
                                                             new-t)))
                                           0)))
    (print :before-result ((. (require :fennel) :view) result))
    result))

(fn m.join [t condition]
  (.. " JOIN " t " ON " condition))

(fn m.where [condition]
  (.. " WHERE " condition))

(fn m.insert [self what v]
  (let [sql (.. "INSERT INTO " what " VALUES (" v ");")]
    (print sql)
    (print :insert (self.connection:exec sql))))

(fn m.update [self t query condition]
  (let [sql (.. "UPDATE " t " SET " query " WHERE " condition ";")]
    (self.connection:exec sql)))

(fn m.delete [self t condition]
  (let [sql (.. "DELETE FROM " t " WHERE " condition ";")]
    (self.connection:exec sql)))

m
