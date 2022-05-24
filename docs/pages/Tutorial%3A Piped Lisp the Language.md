title:: Tutorial: Piped Lisp the Language

- ## A Lisp for Piping Results
- You're encouraged to run `sc -r` on your computer and copy lines starting with `sc>` into the interactive console.
- ### Basic Syntax
- ```
  ; Piped Lisp is dynamically typed, but every value has a type!
  
  sc> nil
  nil
  sc> type nil
  "nil"
  ; 💡 Truthiness: nil and false are falsey,
  ; all other values are truthy.
  
  sc> true
  true
  sc> type true
  "boolean"
  ; 💡 Piped Lisp conditional functions use truthiness,
  ; not strict true/false, for conditions.
  
  sc> 1
  1
  sc> type 1
  "number"
  
  sc> 1.0
  1.0
  sc> type 1.0
  "number"
  ; 💡 Arithmetic ops rely on Dart's semantics.
  
  sc> "abc"
  "abc"
  sc> type "abc"
  "string"
  ; 💡 Strings support whitespace escapes, using backslack,
  ; but not the more advanced ones that Dart strings do.
  
  sc> qwerty
  qwerty
  ^^^^^^ This symbol isn't defined.
  
  Do you want to define it? (y/n) >
  ; 💡 REPL mode allows interactive symbol binding.
  
  sc> .foo
  .foo
  sc> type .foo
  "dotted symbol"
  ; 💡 A dotted symbol is like a Clojure keyword, but with
  ; some extended semantics.
  
  sc> [1 "2" .three]
  [
    1,
    "2",
    .three,
  ]
  sc> type []
  "list"
  
  sc> {.alpha "beta" .gamma ["delta" "epsilon"]}
  {
    .alpha "beta",
    .gamma [
      "delta",
      "epsilon",
    ],
  }
  sc> type {}
  "map"
  
  sc> (fn [])
  nil ; 💡 This is returned because the function is _invoked_
  sc> identity (fn [])
  <function> ; 💡 Function as a value, not invoked
  sc> type (fn [])
  "function"
  
  sc> %(println "Wow!\nThis is neat!")
  Wow!
  This is neat!
  nil
  sc> identity %*()
  <function>
  sc> type %()
  "anonymous function"
  
  sc> dt "2022-01-01T00Z"
  (dt "2022-01-01 00:00:00.000Z")
  sc> type *1
  "date-time"
  
  sc> file "/tmp/abc.txt"
  (file "/tmp/abc.txt")
  sc> type *1
  "file"
  
  ; 💡 In addition to these types, all supported Shortcut entities
  ; have dedicated types: story, epic, milestone, iteration, label,
  ; workflow, workflow state, epic workflow, epic workflow state.
  ```
-
- ### Arithmetic
	- Functions: `+`, `-`, `*`, `/`, `>`, `>=`, `<`, `<=`, `max`, `min`, `mod`
	- TODO Implement `avg`, `sum`, consider std. dev.
- ```
  ; Let's do some math and learn about Piped Lisp!
  
  sc> *
  1
  
  ; Tip: Press the up arrow to get the previous expression.
  
  sc> * 2 3
  ;=> 6
  
  ; Pipe takes the result of one expression and passes it as
  ; the _first_ argument to the next.
  
  sc> * 2 3 | / 3
  2
  
  ; Use an underscore in a top-level expression to change where
  ; the previous result is threaded.
  
  sc> * 2 3 | / 3 _
  0.5
  
  ; Warning: The underscore doesn't work inside of a nested expression,
  ; like a function literal.
  ```
- ### Collections (shared functionality)
	- Functions: `concat`, `contains?`, `count`/`len`/`length`, `get`, `distinct`/`uniq`, `limit`/`take`, `reduce`
	- TODO Implement `reverse`
- ### Strings
	- Functions: `join`, `split`, `concat`
- ### Lists
	- Functions: `map`/`for-each`, `filter`/`where`
- ### Maps
	- Functions: `get-in`, `keys`, `select`
-