; inherits: javascript

((identifier) @variable.builtin
  (#eq? @variable.builtin "db"))

; Operators and stages: { $match: ... }, { "$gt": 1 }
((property_identifier) @keyword.operator
  (#lua-match? @keyword.operator "^%$"))

(pair
  key: (string
    (string_fragment) @keyword.operator
    (#lua-match? @keyword.operator "^%$")))

; Field references: "$address.city"
(pair
  value: (string
    (string_fragment) @variable.member
    (#lua-match? @variable.member "^%$")))

(array
  (string
    (string_fragment) @variable.member
    (#lua-match? @variable.member "^%$")))

; BSON constructors
(call_expression
  function: (identifier) @type.builtin
  (#any-of? @type.builtin
    "ObjectId" "ISODate" "NumberInt" "NumberLong" "NumberDecimal" "Decimal128" "Long" "Int32"
    "Double" "UUID" "Timestamp" "BinData" "MinKey" "MaxKey"))

(new_expression
  constructor: (identifier) @type.builtin
  (#any-of? @type.builtin "ObjectId" "Date" "Timestamp" "UUID"))

; Shell helpers: use <db>, show <what>
(ERROR
  .
  (identifier) @keyword
  (#any-of? @keyword "use" "show"))

(expression_statement
  .
  (identifier) @keyword
  (#any-of? @keyword "use" "show" "it"))
