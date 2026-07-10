;; Used for refactoring legacy python expressions `raise error, "errormessage"`
(raise_statement
  (expression_list 
    (identifier) @error
    (_) @msg
  ) 
)
